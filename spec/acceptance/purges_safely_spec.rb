require 'spec_helper_acceptance'

describe 'package_purging_with_apt' do

  context "With existing packages on the system" do
    before :all do
      pp = <<-EOS
        apply_purge {}
      EOS
      apply_manifest(pp, :expect_changes => true)
    end

    describe port(389) do
      it { is_expected.to be_listening }
    end
  end

end
