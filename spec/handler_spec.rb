require 'spec_helper'

describe RackDAV::Handler do
  let(:handler) { RackDAV::Handler.new }
  let(:request) { Rack::Request.new({ 'REQUEST_METHOD' => 'GET' }) }

  describe "#initialize" do
    it "accepts zero parameters" do
      lambda do
        handler
      end.should_not raise_error
    end

    it "sets options from argument" do
      instance = klass.new :foo => "bar"
      instance.options[:foo].should == "bar"
    end

    it "defaults option :resource_class to FileResource" do
      handler.options[:resource_class].should be(RackDAV::FileResource)
    end

    it "defaults option :root to current directory" do
      path = '/tmp'
      Dir.chdir(path)
      instance = handler
      instance.options[:root].should == path
    end

    it 'sets the response status to 405 if the request method is not allowed' do
      request.env['REQUEST_METHOD'] = 'FOO'
      expect(handler.call(request.env)[0]).to eq(405)
    end
  end

end
