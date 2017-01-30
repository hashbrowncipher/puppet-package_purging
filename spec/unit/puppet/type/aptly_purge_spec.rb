require 'puppet'
require 'spec_helper'

describe Puppet::Type.type(:aptly_purge) do
  before :each do
    @catalog = Puppet::Resource::Catalog.new
    @package = Puppet::Type.type(:package)

    @purge = Puppet::Type.type(:aptly_purge).new(:title => 'packages', :debug => true)
    @catalog.add_resource @purge

    @existing_package = @package.new(:name => 'existing_package')
    allow(@package).to receive(:instances).and_return([@existing_package])

    allow(@purge).to receive(:mark_manual)
    allow(@purge).to receive(:mark_auto)
  end

  it "correctly reads from the autoremover" do
    allow(@purge).to receive(:get_purges).and_return(['existing_package'])
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
    allow(@purge).to receive(:all_packages_synced).and_return(true)
    @test_package = @package.new(:name => 'test_package')
    @catalog.add_resource @test_package
    allow(@package).to receive(:instances).and_return([@existing_package, @test_package])
    expect(@purge).to receive(:mark_manual).with(['test_package'], '/dev/stdout')
    @purge.generate
  end

end
