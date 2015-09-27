Puppet::Type.type(:package).provide :held_apt, :parent => :apt, :source => :dpkg do
  defaultfor :osfamily => :debian

  def self.parse_line(line)
    hash = nil

    if match = self::FIELDS_REGEX.match(line)
      hash = {}

      self::FIELDS.zip(match.captures) do |field,value|
        hash[field] = value
      end

      hash[:provider] = self.name

      if hash[:status] == 'not-installed'
        hash[:ensure] = :purged
      elsif ['config-files', 'half-installed', 'unpacked', 'half-configured'].include?(hash[:status])
        hash[:ensure] = :absent
      end
    else
      Puppet.debug("Failed to match dpkg-query line #{line.inspect}")
    end

    return hash
  end
end
