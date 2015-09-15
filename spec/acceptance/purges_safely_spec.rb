require 'spec_helper_acceptance'

describe 'package_purging_with_apt' do

  context "With existing packages on the system" do
    before :all do
      pp = <<-EOS
        package { 'ubuntu-minimal': }
        aptly_purge { 'packages': }
      EOS
      apply_manifest(pp, :expect_changes => true)
    end

    describe package('openssh-server') do
      it { should_not be_installed }
    end
  end

end
