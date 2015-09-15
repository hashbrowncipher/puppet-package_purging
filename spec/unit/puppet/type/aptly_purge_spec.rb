require 'puppet'

describe Puppet::Type.type(:aptly_purge) do
  before :each do
    @catalog = Puppet::Resource::Catalog.new
    @package = Puppet::Type.type(:package)

    @purge = Puppet::Type.type(:aptly_purge).new(:title => 'packages')
    @catalog.add_resource @purge

    @existing_package = @package.new(:name => 'existing_package')
    @package.stub(:instances) { [@existing_package] }

    @purge.stub(:mark_manual)
    @purge.stub(:mark_auto)
    @purge.stub(:unhold)
  end

  it "correctly reads from the autoremover" do
    @purge.stub(:get_purges) { ['existing_package'] }
    expect(@purge.generate).to eql([@existing_package])
  end

  it "refuses to run when the catalog contains new packages" do
    @test_package = @package.new(:name => 'test_package')
    @catalog.add_resource @test_package
    expect { @purge.generate }.to raise_error(Puppet::Error)
  end

  it "correctly marks existing package as autoinstalled" do
    expect(@purge).to receive(:mark_auto).with(['existing_package'], '/dev/stdout')
    @purge.generate
  end

  it "correctly marks packages in the catalog as manually installed" do
    @purge.stub(:all_packages_synced) { true }
    @test_package = @package.new(:name => 'test_package')
    @catalog.add_resource @test_package
    @package.stub(:instances) { [@existing_package, @test_package] }
    expect(@purge).to receive(:mark_manual).with(['test_package'], '/dev/stdout')
    @purge.generate
  end

end
