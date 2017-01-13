require 'spec_helper_acceptance'

describe 'package_purging_with_apt' do

  context 'aptly_purge with dangling dependencies (packages) on the system' do
    before :all do
      hosts.each do |host|
        # dictd is a dependency of dict-jargon, it's not currently installed
        expect(check_for_package host, 'dictd').to be false
        # install dict-jargon outside of Puppet
        install_package host, 'dict-jargon'
        # uninstalling dict-jargon causes its dependencies to be left behind
        host.uninstall_package 'dict-jargon'
        # in fact, dictd is still around
        expect(check_for_package host, 'dictd').to be true

        # enable purge by default
        create_remote_file host, '/etc/apt/apt.conf.d/99always-purge', "APT::Get::Purge \"true\";\n";
      end
    end

    it 'should run without errors' do
      pp = <<-EOS
        package { 'ubuntu-minimal': }
        aptly_purge { 'packages': }
      EOS
      apply_manifest(pp, :debug => true)
      expect(@result.exit_code).to eq 0
    end

    describe package('dict-jargon') do
      it { should_not be_installed }
    end

    describe package('dictd') do
      it { should_not be_installed }
    end
  end

end
