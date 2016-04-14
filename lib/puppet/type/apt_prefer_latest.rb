Puppet::Type.newtype(:apt_prefer_latest) do
  @doc = <<-EOD
Modifies the default behavior of the Puppet Package type as applied to dpkg
resources. Specifically, it switches all uses of ensure=>present to
ensure=>latest.  By doing so, we can guarantee systems provisioned a while ago
get upgrades, and that brand new systems have the same package versions as old
systems.
EOD

  newparam(:title) do
    # We don't really need a namevar, but Puppet forces us to have one

    newvalues(:packages)
    isnamevar
  end

  def generate
    package = Puppet::Type.type(:package)
    present_packages = catalog.resources.find_all do |r|
      r.is_a?(package) and
      r.provider.is_a?(Puppet::Type::Package::ProviderDpkg)
    end.select do |r|
      r.parameters[:ensure].should == :present
    end

    present_packages.map do |r|
      r.parameters[:ensure].should = :latest
    end

    nil
  end
end
