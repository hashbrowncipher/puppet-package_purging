require 'set'
require 'open3'
require 'puppet/parameter/boolean'


Puppet::Type.newtype(:aptly_purge) do
  @doc = <<-EOD
Interfaces the Puppet package type with apt-mark, generating Puppet resources
in response.  Packages managed by Puppet are marked as manually installed,
those not managed by Puppet are marked as automatically installed.

The apt-get autoremover is then simulated, generating a list of packages to
be removed.  This type takes the resulting list and generates Puppet package
resources with ensure=>absent for any unmanaged resources that apt-get would
autoremove.
EOD

  newparam(:title) do
    # We don't really need a namevar, but Puppet forces us to have one
    newvalues(:packages)

    isnamevar
  end

  newparam(:debug, :boolean => true, :parent => Puppet::Parameter::Boolean) do
    defaultto false
  end

  newparam(:purge, :boolean => true, :parent => Puppet::Parameter::Boolean) do
    defaultto false
  end

  newparam(:hold, :boolean => true, :parent => Puppet::Parameter::Boolean) do
    defaultto false
  end

  def generate
    outfile = @parameters[:debug] ? "/dev/stdout" : "/dev/null"
    package = Puppet::Type.type(:package)


    # Using the RAL, divide the world into Catalog packages and not-Catalog
    # packages.
    managed_packages = []
    unmanaged_packages = []

    package.instances.select do |p|
      p.provider.is_a?(Puppet::Type::Package::ProviderDpkg)
    end.each do |r|
      catalog_r = catalog.resource(r.ref) || find_resource_alias(["Package", r.name, :held_apt])
      if catalog_r.nil?
        unmanaged_packages << r
      else
        managed_packages << catalog_r
      end
    end

    managed_package_names = managed_packages.map(&:name)
    Puppet.debug "managed_package_names: #{managed_package_names}"
    unmanaged_package_names = unmanaged_packages.map(&:name)
    Puppet.debug "unmanaged_package_names: #{unmanaged_package_names}"

    if should_hold? then
      # You can't hold a package that isn't installed yet, so this should
      # really be done after all packages are installed.

      pinned = managed_packages.select do |p|
        # What we really want is to grab all packages with an explicit version
        # This is a cheap reproduction of what we really want.
        ![:latest, :absent, :present].include?(p.parameters[:ensure].value)
      end

      Puppet.debug "pinned: #{pinned.map(&:name)}"
      unless noop?
        holds = pinned.map do |p|
          Puppet::Type.type(:dpkg_hold).new({ :name => p[:name], :ensure => :present })
        end
      end
    else
      holds = []
    end
    Puppet.debug "holds: #{holds.map(&:name)}"

    unless all_packages_synced
      notice <<EOS

It isn't safe to purge packages right now, because there are packages in the
catalog that aren't synced on the system. Package purging is skipped for this
Puppet run.
EOS
      raise Puppet::Error.new("Could not purge packages during this Puppet run")
    end

    # If we don't set managed packages to noauto here, it is possible to
    # set ensure=>absent on an unmanaged package that a managed package
    # depends on.
    # A (in catalog) -> B (not in catalog)
    # B is marked as 'auto' as it should
    # If some other process has marked A as auto, B will get ensure=>absent
    # Then dpkg will remove both A and B.  This is bad!
    if should_purge?
      mark_manual managed_package_names, outfile

      mark_auto unmanaged_package_names, outfile
    end

    apt_would_purge = get_purges()
    Puppet.debug "apt_would_purge: #{apt_would_purge.to_a}"

    if should_purge?
      removes = unmanaged_packages.select do |r|
        # This is the crux.  We intersect the list of packages Puppet isn't
        # managing with the list of packages that apt would purge.
        apt_would_purge.include?(r.name)
      end.each do |resource|
        resource[:ensure] = 'absent'
        @parameters.each do |name, param|
          resource[name] = param.value if param.metaparam?
        end

        resource.purging
        end
    else
      removes = []
    end
    Puppet.debug "removes: #{removes.map(&:name)}"

    # un-hold packages
    if should_hold?
      dpkg_selections = Puppet::Util::Execution.execute('dpkg --get-selections')
      dpkg_selections = Hash[*dpkg_selections.lines.map {|l| l.rstrip.split(/\s+/,2)}.flatten]
      to_be_removed = Hash[removes.map(&:name).zip([])]
      # unmanaged packages that are not already slated for removal
      unholds = unmanaged_packages.select do |p|
        !to_be_removed.include?(p.name)
      end
      # managed packages with ensure => present
      unholds += managed_packages.select do |p|
        p.parameters[:ensure].value == :present
      end
      # if the packages to be un-held are currently held, generate a dpkg_hold resource with ensure => absent
      unholds = unholds.select do |p|
        dpkg_selections.include?(p.name) &&
        dpkg_selections[p.name] == 'hold'
      end.map do |p|
        Puppet::Type.type(:dpkg_hold).new({ :name => p[:name], :ensure => :absent })
      end
    else
      unholds = []
    end
    Puppet.debug "unholds: #{unholds.map(&:name)}"

    holds + unholds + removes
  end

  private

  def all_packages_synced
    package = Puppet::Type.type(:package)
    catalog.resources.find_all do |r|
      r.is_a?(package) and
      r.provider.is_a?(Puppet::Type::Package::ProviderDpkg)
    end.all? do |r|
      ensure_p = r.parameters[:ensure]
      is = ensure_p.retrieve
      ensure_p.insync?(is)
    end
  end

  def mark_manual(packages, outfile)
    unless packages.empty?
      Open3.pipeline_w('xargs apt-mark manual', :out=>outfile) do |i, ts|
        i.puts(packages)
        i.close
        ts[0].value.success? or raise "Failed to apt-mark packages"
      end
    end
  end

  def mark_auto(packages, outfile)
    unless packages.empty?
      Open3.pipeline_w('xargs apt-mark auto', :out=>outfile) do |i, ts|
        i.puts(packages)
        i.close
        ts[0].value.success? or raise "Failed to apt-mark packages"
      end
    end
  end

  def get_purges
    Open3.pipeline_r('apt-get -s autoremove') do |i, ts|
      p = i.each_line.map {|line|
        match = /^Purg (\S*)/.match(line)
        match[1] if match
      }.compact.to_set
      ts[0].value.success? or raise "Failed to simulate apt-get autoremove"
      p
    end
  end

  # ref is of the form: ["Package", "name", :provider]
  # returns nil if no alias exist
  def find_resource_alias ref
    @resource_aliases ||= catalog.instance_variable_get(:@aliases)

    result = @resource_aliases.find do |ref_str, aliases|
      aliases.find do |candidate_ref|
          candidate_ref == ref
      end
    end
    return result.nil? ? nil : catalog.resource(result.first)
  end

  def should_purge?
    @parameters[:purge] && @parameters[:purge].value && !noop?
  end

  def should_hold?
    @parameters[:hold] && @parameters[:hold].value && !noop?
  end
end
