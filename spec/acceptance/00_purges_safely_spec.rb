require 'spec_helper_acceptance'

describe 'package_purging_with_apt' do
  let :package_purging_manifest do
    <<-EOS
      package { 'ubuntu-minimal': }
      package { 'puppetlabs-release-pc1': }
      package { 'puppet-agent': }
      package { 'fortunes': }
      package { 'openssh-server': }
      include package_purging::config
      aptly_purge { 'packages':
        purge => true,
      }
    EOS
  end

  def get_packages_state host
    apt_mark = on(host, 'apt-mark showauto 2>&1').stdout
    result = apt_mark.lines.each_with_object({}) { |line, h| h[line.rstrip] = 'auto' }
    apt_mark = on(host, 'apt-mark showmanual 2>&1').stdout
    apt_mark.lines.each_with_object(result) do |line, h|
      package = line.rstrip
      raise "Package #{package} appears both in apt-mark showauto and showmanual" if h.has_key?(package)
      h[package] = 'manual'
    end
  end

  before :all do
    hosts.each do |host|
      # install dict-jargon outside of Puppet
      install_package host, 'dict-jargon'
      # dictd gets automatically installed as a dependency of dict-jargon
      expect(check_for_package host, 'dictd').to be true
      # Normally, "apt-get autoremove" would only remove dictd if dict-jargon was manually
      # uninstalled, because in that case dictd would become a "dangling dependency".
      # aptly_purge marks any unmanaged package (any package that's been installed outside
      # of Puppet) as automatically installed. This is counter-intuitive: because of aptly_purge
      # manually installed packages are passed to "apt-mark auto" and will have "Auto-Installed: 1"
      # in /var/lib/apt/extended_states .
      # Any "Auto-Installed: 1" package shows up in the output of "apt-get -s autoremove" and,
      # unless included in the Puppet catalog, will be purged by aptly_purge.

      # fortunes is also manually installed but, as opposed to dict-jargon, a corresponding package
      # resource is declared in the manifest. Therefore, aptly_purge will not uninstall fortunes
      # and its tree of dependencies.
      install_package host, 'fortunes'

      # regardless of parse order, aptly_purge will be a noop until
      # the APT::Get::Purge config option is set (which happens on the first puppet run)
      on host, 'puppet config set ordering random'
      on host, 'puppet config print ordering | grep -q random'
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state host
      expect(packages_state['dict-jargon']).to eq 'manual'
      expect(packages_state['dictd']).to eq 'auto'
      expect(packages_state['fortunes']).to eq 'manual'
      expect(check_for_package host, 'ubuntu-minimal').to be true
    end
  end

  context 'aptly_purge with unmanaged packages on the system, first puppet run' do
    it 'should not remove any packages' do
      # aptly_purge generates the list of packages to purge at "parse time"
      # before/require ordering constraints don't work on it
      apply_manifest(package_purging_manifest)
      expect(@result.exit_code).to eq 0
      # The manifest has been applied, no packages will be removed until the next run
      # because the settings at "include package_purging::config" have just been put
      # in place.
      expect(package('dict-jargon')).to be_installed
      expect(package('dictd')).to be_installed
    end

    # Only 'fortunes' is in the catalog.
    # 'dict-jargon' has been installed outside of puppet, 'dictd' is one
    # of its dependencies. 'dict-jargon' gets apt-mark'ed as 'auto'.
    it 'should correctly apt-mark packages' do
      packages_state = get_packages_state default_node
      expect(packages_state['dict-jargon']).to eq 'auto'
      expect(packages_state['dictd']).to eq 'auto'
      expect(packages_state['fortunes']).to eq 'manual'
    end
  end

  context 'aptly_purge with unmanaged packages on the system, second puppet run' do
    it 'should remove unmanaged packages' do
      apply_manifest(package_purging_manifest, :debug => true)
      expect(@result.exit_code).to eq 0
      expect(package('dict-jargon')).to_not be_installed
      expect(package('dictd')).to_not be_installed
      expect(package('fortunes')).to be_installed
      expect(package('fortunes-min')).to be_installed  # a dependency of fortune
    end
  end

  RSpec.shared_examples 'aptly_purge noop' do |test_case|
    let(:test_manifest) {
      m = <<-EOS
          package { 'ubuntu-minimal': }
          package { 'puppetlabs-release-pc1': }
          package { 'puppet-agent': }
          package { 'fortunes': }
          package { 'openssh-server': }
          include package_purging::config
      EOS
      m + test_case
    }

    it 'before puppet runs' do
      install_package default_node, 'dict-jargon'
      # dictd gets automatically installed as a dependency of dict-jargon
      expect(check_for_package default_node, 'dictd').to be true
      packages_state = get_packages_state default_node
      expect(packages_state['dict-jargon']).to eq 'manual'
      expect(packages_state['dict']).to eq 'auto'
      expect(packages_state['fortunes']).to eq 'manual'

      # Purposely mark dict-jargon as auto. We really want it to look like
      # something that could be purged and make sure it gets left alone
      # when running with noop or purge => false .
      on default_node, 'apt-mark auto dict-jargon'
      packages_state = get_packages_state default_node
      expect(packages_state['dict-jargon']).to eq 'auto'
    end

    it 'should not apt-mark packages' do
      apply_manifest(test_manifest, :debug => true)
      expect(@result.exit_code).to eq 0
      packages_state = get_packages_state default_node
      expect(packages_state['dict-jargon']).to eq 'auto'
      expect(packages_state['dict']).to eq 'auto'
      expect(packages_state['fortunes']).to eq 'manual'

      expect(package('dict-jargon')).to be_installed
      expect(package('dictd')).to be_installed
      expect(package('fortunes')).to be_installed
      expect(package('fortunes-min')).to be_installed  # a dependency of fortune
    end
  end

  context 'aptly_purge in noop mode' do
    it_behaves_like 'aptly_purge noop', "aptly_purge { 'packages': noop => true }"
  end

  context 'aptly_purge with purge => false' do
    it_behaves_like 'aptly_purge noop', "aptly_purge { 'packages': purge => false }"
  end

  context 'aptly_purge by default' do
    it_behaves_like 'aptly_purge noop', "aptly_purge { 'packages': }"
  end

end
