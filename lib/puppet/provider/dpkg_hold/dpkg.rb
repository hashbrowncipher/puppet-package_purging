Puppet::Type.type(:dpkg_hold).provide(:dpkg) do
  self::DPKG_QUERY_FORMAT_STRING = %Q{'${Status} ${Package}\\n'}
  self::FIELDS_REGEX = %r{^(\S+) +(\S+) +(\S+) (\S+)$}
  self::FIELDS= [:desired, :error, :status, :name]

  commands :dpkgquery => "/usr/bin/dpkg-query"
  commands :dpkg => "/usr/bin/dpkg"

  # Performs a dpkgquery call with a pipe so that output can be processed
  # inline in a passed block.
  # @param args [Array<String>] any command line arguments to be appended to the command
  # @param block expected to be passed on to execpipe
  # @return whatever the block returns
  # @see Puppet::Util::Execution.execpipe
  # @api private
  def self.dpkgquery_piped(*args, &block)
    cmd = args.unshift(command(:dpkgquery))
    Puppet::Util::Execution.execpipe(cmd, &block)
  end

  def self.instances
    packages = []

    # list out all of the packages
    dpkgquery_piped('-W', '--showformat', self::DPKG_QUERY_FORMAT_STRING) do |pipe|
      # now turn each returned line into a package object
      pipe.each_line do |line|
        if hash = parse_line(line)
          packages << new(hash)
        end
      end
    end

    packages
  end

  # @param line [String] one line of dpkg-query output
  # @return [Hash,nil] a hash of FIELDS or nil if we failed to match
  # @api private
  def self.parse_line(line)
    hash = nil

    if match = self::FIELDS_REGEX.match(line)
      hash = {}

      self::FIELDS.zip(match.captures) do |field,value|
        hash[field] = value
      end

      hash[:provider] = self.name
    else 
      Puppet.debug("Failed to match dpkg-query line #{line.inspect}")
    end

    return hash
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    Tempfile.open('puppet_dpkg_set_selection') do |tmpfile|
      tmpfile.write("#{@resource[:name]} hold\n")
      tmpfile.flush
      execute([:dpkg, "--set-selections"], :failonfail => false, :combine => false, :stdinfile => tmpfile.path.to_s)
    end
  end

  def destroy
    Tempfile.open('puppet_dpkg_set_selection') do |tmpfile|
      tmpfile.write("#{@resource[:name]} install\n")
      tmpfile.flush
      execute([:dpkg, "--set-selections"], :failonfail => false, :combine => false, :stdinfile => tmpfile.path.to_s)
    end
  end
end
