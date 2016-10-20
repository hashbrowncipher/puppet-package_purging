Puppet::Type.newtype(:dpkg_hold) do
  @doc = "Mark a dpkg package as held"

  ensurable

  newparam(:name) do
     desc "The name of the package."
  end

  autorequire(:package) do
    self[:name]
  end
end
