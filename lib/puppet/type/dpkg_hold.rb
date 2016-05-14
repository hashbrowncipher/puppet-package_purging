Puppet::Type.newtype(:dpkg_hold) do
  @doc = "Mark a dpkg package as held"

  ensurable

  autorequire(:package) do
    self[:title]
  end
end
