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

  def generate
    (managed_packages, unmanaged_packages) = Puppet::Type.type('package').instances.select do |p|
      ['apt', 'aptitude'].include?(p.provider.class.name.to_s)
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
    Open3.pipeline_w('xargs apt-mark manual') do |i, ts|
      i.puts(managed_packages.map(&:name))
      i.close
      ts[0].value.success? or raise "Failed to apt-mark packages"
    end

    # It would be excellent to set 'apt-mark hold' on all managed packages
    # here, but it turns out this doesn't interact well with dpkg based
    # package providers.

    Open3.pipeline_w('xargs apt-mark auto') do |i, ts|
      i.puts(unmanaged_package_names)
      i.close
      ts[0].value.success? or raise "Failed to apt-mark packages"
    end

    Open3.pipeline_w('xargs apt-mark unhold') do |i, ts|
      i.puts(unmanaged_package_names)
      i.close
      ts[0].value.success? or raise "Failed to apt-mark packages"
    end

    apt_would_purge = Open3.pipeline_r('apt-get -s autoremove') do |i, ts|
      p = i.each_line.map {|line|
        match = /^Purg (\S*)/.match(line)
	match[1] if match
      }.compact.to_set
      ts[0].value.success? or raise "Failed to simulate apt-get autoremove"
      p
    end

    unmanaged_packages.select do |r|
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
  end
end
