require 'spec_helper_acceptance'

describe 'package_purging_with_apt' do
  let :package_purging_manifest do
    <<-EOS
      package { 'ubuntu-minimal': }
      package { 'puppetlabs-release-pc1': }
      package { 'puppet-agent': }
      package { 'fortunes': }
      include package_purging::config
      aptly_purge { 'packages': }
    EOS
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
    end
  end

  describe package('ubuntu-minimal') do
    it { should be_installed }
  end

  context 'aptly_purge with unmanaged packages on the system, first puppet run' do
    it 'should not remove any packages' do
      # aptly_purge generates the list of packages to purge at "parse time"
      # before/require ordering constraints don't work on it
      apply_manifest(package_purging_manifest)
      expect(@result.exit_code).to eq 0
    end

    describe package('dict-jargon') do
      it { should be_installed }
    end
    describe package('dictd') do
      it { should be_installed }
    end
  end

  context 'aptly_purge with unmanaged packages on the system, second puppet run' do
    it 'should remove unmanaged packages' do
      apply_manifest(package_purging_manifest, :debug => true)
      expect(@result.exit_code).to eq 0
    end

    describe package('dict-jargon') do
      it { should_not be_installed }
    end
    describe package('dictd') do
      it { should_not be_installed }
    end
    describe package('fortunes') do
      it { should be_installed }
    end
    describe package('fortunes-min') do  # a dependency of fortunes
      it { should be_installed }
    end
  end

end
