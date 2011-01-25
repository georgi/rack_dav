require 'spec_helper'

describe RackDAV::Handler do

  describe "#initialize" do
    it "accepts zero parameters" do
      lambda do
        klass.new
      end.should_not raise_error
    end

    it "accepts a hash of options" do
      lambda do
        klass.new({})
        klass.new :foo => "bar"
      end.should_not raise_error
    end

    it "sets options from argument" do
      instance = klass.new :foo => "bar"
      instance.options[:foo].should == "bar"
    end

    it "defaults option :resource_class to FileResource" do
      instance = klass.new
      instance.options[:resource_class].should be(RackDAV::FileResource)
    end

    it "defaults option :root to current directory" do
      path = File.expand_path("../../bin", __FILE__)
      Dir.chdir(path)
      instance = klass.new
      instance.options[:root].should == path
    end
  end

end
