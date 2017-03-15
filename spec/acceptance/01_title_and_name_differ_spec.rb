require 'spec_helper_acceptance'

describe 'title_and_name_differ' do
  before :all do
    hosts.each do |host|
      install_package host, 'dict-jargon'
      expect(check_for_package host, 'dictd').to be true
      install_package host, 'fortunes'
      expect(check_for_package host, 'fortunes-min').to be true
      # same as `include package_purging::config`, saves a Puppet run
      create_remote_file host, '/etc/apt/apt.conf.d/99always-purge', "APT::Get::Purge \"true\";\n";
    end
  end

  context 'manifest contains a package resource where title != name' do
    it 'should apply' do
      m = <<-EOS
        package { 'ubuntu-minimal': }
        package { 'puppetlabs-release-pc1': }
        package { 'puppet-agent': }
        package { 'openssh-server': }
        package {'fortunespkg':
          name => 'fortunes',
        }
        aptly_purge {'packages':
          purge => true,
        }
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0
      expect(package('dict-jargon')).to_not be_installed
      expect(package('dictd')).to_not be_installed
      expect(package('fortunes')).to be_installed
      expect(package('fortunes-min')).to be_installed  # a dependency of fortune
    end
  end
end
