require 'open3'
require 'puppet/parameter/boolean'
require 'set'

Puppet::Type.newtype(:aptly_purge) do
  @doc = <<-EOD
Interfaces the Puppet package type with apt-mark, generating Puppet resources
in response.  Packages managed by Puppet are marked as manually installed,
those not managed by Puppet are marked as automatically installed.

The apt-get autoremover is then simulated, generating a list of packages to
be removed.  This type takes the resulting list and generates Puppet package
resources with ensure=>absent for any unmanaged resources that apt-get would
autoremove.

NOTE: This type writes into the apt-mark system, even when run in noop mode.
EOD

  newparam(:title) do
    # We don't really need a namevar, but Puppet forces us to have one
    newvalues(:packages)

    isnamevar
  end

  newparam(:debug, :boolean => true, :parent => Puppet::Parameter::Boolean) do
    defaultto false
  end

  newparam(:whitelist, :array_matching => :all) do
    validate do |value|
      unless value.is_a? Array
        raise ArgumentError, "whitelist must be a list"
      else
        super value
      end
    end
  end

  def generate
    outfile = @parameters[:debug] ? "/dev/stdout" : "/dev/null"
    package = Puppet::Type.type(:package)

    unless all_packages_synced
      warning <<EOS

It isn't safe to purge packages right now, because there are packages in the
catalog that aren't synced on the system. Package purging is skipped for this
Puppet run.
EOS
      raise Puppet::Error.new("Could not purge packages during this Puppet run")
    end

    # Using the RAL, divide the world into Catalog packages and not-Catalog
    # packages.
    (managed_packages, unmanaged_packages) = package.instances.select do |p|
      p.provider.is_a?(Puppet::Type::Package::ProviderDpkg)
    end.partition { |r| catalog.resource_refs.include? r.ref }

    managed_package_names = managed_packages.map(&:name)
    unmanaged_package_names = unmanaged_packages.map(&:name)

    # If we don't set managed packages to noauto here, it is possible to
    # set ensure=>absent on an unmanaged package that a managed package
    # depends on.
    # A (in catalog) -> B (not in catalog)
    # B is marked as 'auto' as it should
    # If some other process has marked A as auto, B will get ensure=>absent
    # Then dpkg will remove both A and B.  This is bad!
    mark_manual managed_package_names, outfile

    # It would be excellent to set 'apt-mark hold' on all managed packages
    # here, but it turns out this doesn't interact well with dpkg based
    # package providers.

    mark_auto unmanaged_package_names, outfile

    unhold unmanaged_package_names, outfile

    apt_would_purge = get_purges()

    whitelist = @parameters[:whitelist]
    unless whitelist.nil? then
      whitelist = whitelist.value.to_set
    end

    unmanaged_packages.select do |r|
      # This is the crux.  We intersect the list of packages Puppet isn't
      # managing with the list of packages that apt would purge.
      apt_would_purge.include?(r.name) and
      (whitelist.nil? or whitelist.include?(r.name))
    end.each do |resource|
      resource[:ensure] = 'absent'
      @parameters.each do |name, param|
        resource[name] = param.value if param.metaparam?
      end

      resource.purging
    end
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
    Open3.pipeline_w('xargs apt-mark manual', :out=>outfile) do |i, ts|
      i.puts(packages)
      i.close
      ts[0].value.success? or raise "Failed to apt-mark packages"
    end
  end

  def mark_auto(packages, outfile)
    Open3.pipeline_w('xargs apt-mark auto', :out=>outfile) do |i, ts|
      i.puts(packages)
      i.close
      ts[0].value.success? or raise "Failed to apt-mark packages"
    end
  end

  def unhold(packages, outfile)
    Open3.pipeline_w('xargs apt-mark unhold', :out=>outfile) do |i, ts|
      i.puts(packages)
      i.close
      ts[0].value.success? or raise "Failed to apt-mark packages"
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
end
