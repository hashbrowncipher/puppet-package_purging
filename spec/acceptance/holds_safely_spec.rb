require 'spec_helper_acceptance'

describe 'package_holding_with_apt' do
  def get_installed_version host, package_name
    line = on(host, "dpkg -s #{package_name} | grep ^Version").stdout
    version = line.gsub(/\s+/,'').split(':',2).last
    version.empty? ? nil : version
  end

  def get_candidate_version host, package_name
    line = on(host, "apt-cache policy #{package_name} | grep Candidate: | head -1").stdout
    version = line.gsub(/\s+/,'').split(':',2).last
    version.empty? ? nil : version
  end

  def get_packages_state host
    packages_state = on(host, 'dpkg-query -W --showformat \'${Status} ${Package}\n\'').stdout
    packages_state.lines.each_with_object({}) do |line, h|
      if match = line.match(/^(\S+) +(\S+) +(\S+) (\S+)$/)
        desired, error, status, name = match.captures
        h[name] = desired
      end
    end
  end

  def set_package_state host, package, state
    on(host, "echo #{package} #{state} | dpkg --set-selections")
  end

  before :all do
    @managed_packages = [
      'ubuntu-minimal',
      'puppetlabs-release-pc1',
      'puppet-agent',
      'openssh-server',
      'dict-jargon',
      'fortunes',
    ]
    @package_versions = {}

    hosts.each do |host|
      install_package host, 'dict-jargon'
      expect(check_for_package host, 'dictd').to be true
      install_package host, 'fortunes'
      expect(check_for_package host, 'fortunes-min').to be true
      # same as `include package_purging::config`, saves a Puppet run
      create_remote_file host, '/etc/apt/apt.conf.d/99always-purge', "APT::Get::Purge \"true\";\n";

      @managed_packages.each do |p|
        @package_versions[p] = get_installed_version(host, p) || get_candidate_version(host, p)
      end

      @managed_packages.each do |p|
        set_package_state default_node, p, 'install'
      end
      packages_state = get_packages_state default_node
      expect(packages_state.values_at(*@managed_packages)).to eq(['install'] * @managed_packages.length)
    end
  end

  context 'manifest manages a few packages, all of them pin a specific version' do
    it 'should hold all the packages' do
      managed_packages = @managed_packages
      m = @package_versions.map do |p, v|
        "package { '#{p}': ensure => '#{v}' }"
      end.join("\n")
      m += <<-EOS

        aptly_purge {'packages':
          hold => true,
        }
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state default_node
      # our packages are held
      expect(packages_state.values_at(*managed_packages)).to eq(['hold'] * managed_packages.length)
      # everything else isn't
      expect(packages_state.values_at(*(packages_state.keys - managed_packages))).not_to include('hold')
    end
  end

  context '"fortunes" is not managed' do
    it 'should stop holding "fortunes" as it\'s no longer in the manifest' do
      managed_packages = @managed_packages - ['fortunes']
      m = managed_packages.map do |p|
        "package { '#{p}': ensure => '#{@package_versions[p]}' }"
      end.join("\n")
      m += <<-EOS

        aptly_purge {'packages':
          hold => true,
        }
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state default_node
      # managed packages are held
      expect(packages_state.values_at(*managed_packages)).to eq(['hold'] * managed_packages.length)
      # fortunes isn't
      expect(packages_state['fortunes']).to eq('install')
      # because the "purge" parameter defaults to false, the package is still installed
      expect(package('fortunes')).to be_installed
    end
  end

  context 'in the manifest, "fortunes" is set to ensure => present' do
    it 'should not hold "fortunes" as it\'s not pinned to a specific version' do
      pinned_packages = @managed_packages - ['fortunes']
      m = pinned_packages.map do |p|
        "package { '#{p}': ensure => '#{@package_versions[p]}' }"
      end.join("\n")
      m += <<-EOS

        package{'fortunes': ensure => present}
        aptly_purge {'packages':
          hold => true,
        }
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state default_node
      # pinned packages are held
      expect(packages_state.values_at(*pinned_packages)).to eq(['hold'] * pinned_packages.length)
      # fortunes isn't
      expect(packages_state['fortunes']).to eq('install')
      expect(package('fortunes')).to be_installed
    end
  end

  context '"fortunes" used to be held, now it is set to ensure => present' do
    it 'should not hold "fortunes" as it\'s not pinned to a specific version' do
      set_package_state default_node, 'fortunes', 'hold'
      packages_state = get_packages_state default_node
      expect(packages_state['fortunes']).to eq('hold')

      pinned_packages = @managed_packages - ['fortunes']
      m = pinned_packages.map do |p|
        "package { '#{p}': ensure => '#{@package_versions[p]}' }"
      end.join("\n")
      m += <<-EOS

        package{'fortunes': ensure => present}
        aptly_purge {'packages':
          hold => true,
        }
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state default_node
      # pinned packages are held
      expect(packages_state.values_at(*pinned_packages)).to eq(['hold'] * pinned_packages.length)
      # fortunes isn't
      expect(packages_state['fortunes']).to eq('install')
      # because the "purge" parameter defaults to false, the package is still installed
      expect(package('fortunes')).to be_installed
    end
  end

  context 'un-holding "fortunes" when declared with title != name' do
    it 'should not hold "fortunes" as it\'s not pinned to a specific version' do
      set_package_state default_node, 'fortunes', 'hold'
      packages_state = get_packages_state default_node
      expect(packages_state['fortunes']).to eq('hold')

      pinned_packages = @managed_packages - ['fortunes']
      m = pinned_packages.map do |p|
        "package { '#{p}': ensure => '#{@package_versions[p]}' }"
      end.join("\n")
      m += <<-EOS

        package {'fortunespkg':
          name => 'fortunes',
          ensure => present,
        }
        aptly_purge {'packages':
          hold => true,
        }
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state default_node
      # pinned packages are held
      expect(packages_state.values_at(*pinned_packages)).to eq(['hold'] * pinned_packages.length)
      # fortunes isn't
      expect(packages_state['fortunes']).to eq('install')
      # because the "purge" parameter defaults to false, the package is still installed
      expect(package('fortunes')).to be_installed
    end
  end


  RSpec.shared_examples 'aptly_purge (hold) noop' do |test_case|
    it 'maeks no changes' do
      managed_packages = @managed_packages

      managed_packages.each do |p|
        set_package_state default_node, p, 'install'
      end
      packages_state = get_packages_state default_node
      expect(packages_state.values_at(*managed_packages)).to eq(['install'] * managed_packages.length)

      m = managed_packages.map do |p|
        "package { '#{p}': ensure => '#{@package_versions[p]}' }"
      end.join("\n")
      m += <<-EOS

        #{test_case}
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state default_node
      # no managed/pinned packages are held
      expect(packages_state.values_at(*managed_packages)).to eq(['install'] * managed_packages.length)
      # so do all the other packages on the system
      expect(packages_state.values_at(*(packages_state.keys - managed_packages))).not_to include('hold')
    end
  end

  context 'aptly_purge (hold) in noop mode' do
    it_behaves_like 'aptly_purge (hold) noop', "aptly_purge { 'packages': noop => true }"
  end

  context 'aptly_purge (hold) with hold => false' do
    it_behaves_like 'aptly_purge (hold) noop', "aptly_purge { 'packages': hold => false }"
  end

  context 'aptly_purge (hold) by default' do
    it_behaves_like 'aptly_purge (hold) noop', "aptly_purge { 'packages': }"
  end
end
