require 'spec_helper'
require 'fileutils'

require 'rack/mock'

require 'support/lockable_file_resource'

# This is required to be able to send bare plus symbols in mock
# request URLs
class Rack::MockRequest
  @parser = URI
end

class Rack::MockResponse

  attr_reader :original_response

  def initialize_with_original(*args)
    status, headers, @original_response = *args
    initialize_without_original(*args)
  end

  alias_method :initialize_without_original, :initialize
  alias_method :initialize, :initialize_with_original

  def media_type_params
    return {} if content_type.nil?
    Hash[*content_type.split(/\s*[;,]\s*/)[1..-1].
         collect { |s| s.split('=', 2) }.
         map { |k,v| [k.downcase, v] }.flatten]
  end

end

if ENV['TRAVIS']
  RSpec.configure do |c|
    c.filter_run_excluding :has_xattr_support => true
  end
end

describe RackDAV::Handler do

  DOC_ROOT = File.expand_path(File.dirname(__FILE__) + '/htdocs')
  METHODS = %w(GET PUT POST DELETE PROPFIND PROPPATCH MKCOL COPY MOVE OPTIONS HEAD LOCK UNLOCK)
  CLASS_2 = METHODS
  CLASS_1 = CLASS_2 - %w(LOCK UNLOCK)

  before do
    FileUtils.mkdir(DOC_ROOT) unless File.exists?(DOC_ROOT)
  end

  after do
    FileUtils.rm_rf(DOC_ROOT) if File.exists?(DOC_ROOT)
  end

  attr_reader :response

  shared_examples :lockable_resource do


    describe "OPTIONS" do
      it "is successful" do
        options(url_root).should be_ok
      end

      it "sets the allow header with class 2 methods" do
        options(url_root)
        CLASS_2.each do |method|
          response.headers['allow'].should include(method)
        end
      end
    end

    describe "LOCK" do
      before(:each) do
        put(url_root + 'test', :input => "body").should be_created
        lock(url_root + 'test', :input => File.read(fixture("requests/lock.xml")))
      end

      describe "creation" do
        it "succeeds" do
          response.should be_ok
        end

        it "sets a compliant rack response" do
          body = response.original_response.body
          body.should be_a(Array)
          expect(body.size).to eq(1)
        end

        it "prints the lockdiscovery" do
          lockdiscovery_response response_locktoken
        end
      end

      describe "refreshing" do
        context "a valid locktoken" do
          it "prints the lockdiscovery" do
            token = response_locktoken
            lock(url_root + 'test', 'HTTP_IF' => "(#{token})").should be_ok
            lockdiscovery_response token
          end

          it "accepts it without parenthesis" do
            token = response_locktoken
            lock(url_root + 'test', 'HTTP_IF' => token).should be_ok
            lockdiscovery_response token
          end

          it "accepts it with excess angular braces (office 2003)" do
            token = response_locktoken
            lock(url_root + 'test', 'HTTP_IF' => "(<#{token}>)").should be_ok
            lockdiscovery_response token
          end
        end

        context "an invalid locktoken" do
          it "bails out" do
            lock(url_root + 'test', 'HTTP_IF' => '123')
            response.should be_forbidden
            response.body.should be_empty
          end
        end

        context "no locktoken" do
          it "bails out" do
            lock(url_root + 'test')
            response.should be_bad_request
            response.body.should be_empty
          end
        end

      end
    end

    describe "UNLOCK" do
      before(:each) do
        put(url_root + 'test', :input => "body").should be_created
        lock(url_root + 'test', :input => File.read(fixture("requests/lock.xml"))).should be_ok
      end

      context "given a valid token" do
        before(:each) do
          token = response_locktoken
          unlock(url_root + 'test', 'HTTP_LOCK_TOKEN' => "(#{token})")
        end

        it "unlocks the resource" do
          response.should be_no_content
        end
      end

      context "given an invalid token" do
        before(:each) do
          unlock(url_root + 'test', 'HTTP_LOCK_TOKEN' => '(123)')
        end

        it "bails out" do
          response.should be_forbidden
        end
      end

      context "given no token" do
        before(:each) do
          unlock(url_root + 'test')
        end

        it "bails out" do
          response.should be_bad_request
        end
      end

    end
  end


  context "Given a Lockable resource" do
    context "when mounted directly" do
      before do
        @controller = RackDAV::Handler.new(
          :root           => DOC_ROOT,
          :resource_class => RackDAV::LockableFileResource
        )
      end
      
      let(:url_root){ '/' }
      include_examples :lockable_resource
    end

    context "When mounted via a URLMap" do
      before do
        @controller = Rack::URLMap.new(
          "/dav" => RackDAV::Handler.new(
            :root           => DOC_ROOT,
            :resource_class => RackDAV::LockableFileResource
          )
        )
      end
      
      let(:url_root){ '/dav/' }
      include_examples :lockable_resource
    end
  end

  shared_examples :not_lockable_resource do
    describe "uri escaping" do
      it "allows url escaped utf-8" do
        put(url_root + 'D%C3%B6ner').should be_created
        get(url_root + 'D%C3%B6ner').should be_ok
      end

      it "allows url escaped iso-8859" do
        put(url_root + 'D%F6ner').should be_created
        get(url_root + 'D%F6ner').should be_ok
      end

      it "treats '+' and '%20' as space" do
        mkcol(url_root + 'folder+1').should be_created
        put(url_root + 'folder+1/test+1').should be_created
        get(url_root + "folder+1/test+1").should be_ok
        get(url_root + "#{url_escape 'folder 1'}/#{url_escape 'test 1'}").should be_ok
        get(url_root + "folder%201/test%201").should be_ok

        mkcol(url_root + 'folder%202').should be_created
        put(url_root + 'folder%202/test%202').should be_created
        get(url_root + "folder+2/test+2").should be_ok
        get(url_root + "#{url_escape 'folder 2'}/#{url_escape 'test 2'}").should be_ok
        get(url_root + "folder%202/test%202").should be_ok
      end

      it "treats '%2B' as a plus" do
        mkcol(url_root + 'folder%2B3').should be_created
        put(url_root + 'folder%2B3/test%2B3').should be_created
        get(url_root + "folder%2B3/test%2B3").should be_ok
        get(url_root + "#{url_escape 'folder+3'}/#{url_escape 'test+3'}").should be_ok
        get(url_root + "folder+3/test+3").should_not be_ok

        mkcol(url_root + url_escape('folder+4')).should be_created
        put(url_root + "#{url_escape 'folder+4'}/#{url_escape 'test+4'}").should be_created
        get(url_root + "#{url_escape 'folder+3'}/#{url_escape 'test+3'}").should be_ok
        get(url_root + "folder%2B4/test%2B4").should be_ok
        get(url_root + "folder+4/test+4").should_not be_ok
      end
    end

    describe "OPTIONS" do
      it "is successful" do
        options(url_root).should be_ok
      end

      it "sets the allow header with class 2 methods" do
        options(url_root)
        CLASS_1.each do |method|
          response.headers['allow'].should include(method)
        end
      end
    end

    describe "CONTENT-MD5 header exists" do
      context "doesn't match with body's checksum" do
        before do
          put(url_root + 'foo', :input => 'bar',
                                'HTTP_CONTENT_MD5' => 'baz')
        end

        it 'should return a Bad Request response' do
          response.should be_bad_request
        end

        it 'should not create the resource' do
          get(url_root + 'foo').should be_not_found
        end
      end

      context "matches with body's checksum" do
        before do
          put(url_root + 'foo', :input => 'bar',
                                'HTTP_CONTENT_MD5' => 'N7UdGUp1E+RbVvZSTy1R8g==')
        end

        it 'should be successful' do
          response.should be_created
        end

        it 'should create the resource' do
          get(url_root + 'foo').should be_ok
          response.body.should == 'bar'
        end
      end
    end

    it 'should return headers' do
      put(url_root + 'test.html', :input => '<html/>').should be_created
      head(url_root + 'test.html').should be_ok

      response.headers['etag'].should_not be_nil
      response.headers['content-type'].should match(/html/)
      response.headers['last-modified'].should_not be_nil
    end


    it 'should not find a nonexistent resource' do
      get(url_root + 'not_found').should be_not_found
    end

    it 'should not allow directory traversal' do
      get(url_root + '../htdocs').should be_forbidden
    end

    it 'should create a resource and allow its retrieval' do
      put(url_root + 'test', :input => 'body').should be_created
      get(url_root + 'test').should be_ok
      response.body.should == 'body'
    end

    it 'should create and find a url with escaped characters' do
      put(url_root + url_escape('/a b'), :input => 'body').should be_created
      get(url_root + url_escape('/a b')).should be_ok
      response.body.should == 'body'
    end

    it 'should delete a single resource' do
      put(url_root + 'test', :input => 'body').should be_created
      delete(url_root + 'test').should be_no_content
    end

    it 'should delete recursively' do
      mkcol(url_root + 'folder').should be_created
      put(url_root + 'folder/a', :input => 'body').should be_created
      put(url_root + 'folder/b', :input => 'body').should be_created

      delete(url_root + 'folder').should be_no_content
      get(url_root + 'folder').should be_not_found
      get(url_root + 'folder/a').should be_not_found
      get(url_root + 'folder/b').should be_not_found
    end

    it 'should return not found when deleting a non-existent resource' do
      delete(url_root + 'not_found').should be_not_found
    end

    it 'should not allow copy to another domain' do
      put(url_root + 'test', :input => 'body').should be_created
      copy('http://example.org' + url_root, 'HTTP_DESTINATION' => 'http://another/').should be_bad_gateway
    end

    it 'should not allow copy to the same resource' do
      put(url_root + 'test', :input => 'body').should be_created
      copy(url_root + 'test', 'HTTP_DESTINATION' => url_root + 'test').should be_forbidden
    end

    it 'should not allow an invalid destination uri' do
      put(url_root + 'test', :input => 'body').should be_created
      copy(url_root + 'test', 'HTTP_DESTINATION' => '%').should be_bad_request
    end

    it 'should copy a single resource' do
      put(url_root + 'test', :input => 'body').should be_created
      copy(url_root + 'test', 'HTTP_DESTINATION' => url_root + 'copy').should be_created
      get(url_root + 'copy').body.should == 'body'
    end

    it 'should copy a resource with escaped characters' do
      put(url_root + url_escape('/a b'), :input => 'body').should be_created
      copy(url_root + url_escape('/a b'), 'HTTP_DESTINATION' => url_root + url_escape('/a c')).should be_created
      get(url_root + url_escape('/a c')).should be_ok
      response.body.should == 'body'
    end

    it 'should deny a copy without overwrite' do
      put(url_root + 'test', :input => 'body').should be_created
      put(url_root + 'copy', :input => 'copy').should be_created
      copy(url_root + 'test', 'HTTP_DESTINATION' => url_root + 'copy', 'HTTP_OVERWRITE' => 'F').should be_precondition_failed

      get(url_root + 'copy').body.should == 'copy'
    end

    it 'should allow a copy with overwrite' do
      put(url_root + 'test', :input => 'body').should be_created
      put(url_root + 'copy', :input => 'copy').should be_created
      copy(url_root + 'test', 'HTTP_DESTINATION' => url_root + 'copy', 'HTTP_OVERWRITE' => 'T').should be_no_content
      get(url_root + 'copy').body.should == 'body'
    end

    it 'should deny a move to an existing resource without overwrite' do
      put(url_root + 'test', :input => 'body').should be_created
      put(url_root + 'copy', :input => 'copy').should be_created
      move(url_root + 'test', 'HTTP_DESTINATION' => url_root + 'copy', 'HTTP_OVERWRITE' => 'F').should be_precondition_failed
    end

    it 'should copy a collection' do
      mkcol(url_root + 'folder').should be_created
      copy(url_root + 'folder', 'HTTP_DESTINATION' => url_root + 'copy').should be_created
      propfind(url_root + 'copy', :input => propfind_xml(:resourcetype))
      multistatus_response('/d:propstat/d:prop/d:resourcetype/d:collection').should_not be_empty
    end

    it 'should copy a collection resursively' do
      mkcol(url_root + 'folder').should be_created
      put(url_root + 'folder/a', :input => 'A').should be_created
      put(url_root + 'folder/b', :input => 'B').should be_created

      copy(url_root + 'folder', 'HTTP_DESTINATION' => url_root + 'copy').should be_created
      propfind(url_root + 'copy', :input => propfind_xml(:resourcetype))
      multistatus_response('/d:propstat/d:prop/d:resourcetype/d:collection').should_not be_empty

      get(url_root + 'copy/a').body.should == 'A'
      get(url_root + 'copy/b').body.should == 'B'
    end

    it 'should move a collection recursively' do
      mkcol(url_root + 'folder').should be_created
      put(url_root + 'folder/a', :input => 'A').should be_created
      put(url_root + 'folder/b', :input => 'B').should be_created

      move(url_root + 'folder', 'HTTP_DESTINATION' => url_root + 'move').should be_created
      propfind(url_root + 'move', :input => propfind_xml(:resourcetype))
      multistatus_response('/d:propstat/d:prop/d:resourcetype/d:collection').should_not be_empty

      get(url_root + 'move/a').body.should == 'A'
      get(url_root + 'move/b').body.should == 'B'
      get(url_root + 'folder/a').should be_not_found
      get(url_root + 'folder/b').should be_not_found
    end

    it 'should not move a collection onto an existing collection without overwrite' do
      mkcol(url_root + 'folder').should be_created
      mkcol(url_root + 'dest').should be_created

      move(url_root + 'folder', 'HTTP_DESTINATION' => url_root + 'dest', 'HTTP_OVERWRITE' => 'F').should be_precondition_failed
    end

    it 'should create a collection' do
      mkcol(url_root + 'folder').should be_created
      propfind(url_root + 'folder', :input => propfind_xml(:resourcetype))
      multistatus_response('/d:propstat/d:prop/d:resourcetype/d:collection').should_not be_empty
    end

    it 'should not create a collection with a body' do
      mkcol(url_root + 'folder', :input => 'body').should be_unsupported_media_type
    end

    it 'should not find properties for nonexistent resources' do
      propfind(url_root + 'non').should be_not_found
    end

    it 'should find all properties' do
      xml = render do |xml|
        xml.propfind('xmlns' => "DAV:") do
          xml.allprop
        end
      end

      propfind('http://example.org' + url_root, :input => xml)

      multistatus_response('/d:href').first.text.strip.should == 'http://example.org' + url_root

      props = %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength)
      props.each do |prop|
        multistatus_response('/d:propstat/d:prop/d:' + prop).should_not be_empty
      end
    end

    it 'should find named properties' do
      put(url_root + 'test.html', :input => '<html/>').should be_created
      propfind(url_root + 'test.html', :input => propfind_xml(:getcontenttype, :getcontentlength))

      multistatus_response('/d:propstat/d:prop/d:getcontenttype').first.text.should == 'text/html'
      multistatus_response('/d:propstat/d:prop/d:getcontentlength').first.text.should == '7'
    end

    it 'should set custom properties in the dav namespace', :has_xattr_support => true do
      put(url_root + 'prop', :input => 'A').should be_created
      proppatch(url_root + 'prop', :input => propset_xml([:foo, 'testing']))
      multistatus_response('/d:propstat/d:prop/d:foo').should_not be_empty

      propfind(url_root + 'prop', :input => propfind_xml(:foo))
      multistatus_response('/d:propstat/d:prop/d:foo').first.text.should == 'testing'
    end

    it 'should set custom properties in custom namespaces', :has_xattr_support => true do
      xmlns = { 'xmlns:s' => 'SPEC:' }
      put(url_root + 'prop', :input => 'A').should be_created
      proppatch(url_root + 'prop', :input => propset_xml(['s:foo'.to_sym, 'testing', xmlns]))
      multistatus_response('/d:propstat/d:prop/s:foo', xmlns).should_not be_empty

      propfind(url_root + 'prop', :input => propfind_xml(['s:foo'.to_sym, xmlns]))
      multistatus_response('/d:propstat/d:prop/s:foo', xmlns).first.text.should == 'testing'
    end

    it 'should copy custom properties', :has_xattr_support => true do
      xmlns = { 'xmlns:s' => 'SPEC:' }
      put(url_root + 'prop', :input => 'A').should be_created
      proppatch(url_root + 'prop', :input => propset_xml(['s:foo'.to_sym, 'testing', xmlns]))
      multistatus_response('/d:propstat/d:prop/s:foo', xmlns).should_not be_empty

      copy(url_root + 'prop', 'HTTP_DESTINATION' => url_root + 'propcopy').should be_created
      propfind(url_root + 'propcopy', :input => propfind_xml(['s:foo'.to_sym, xmlns]))
      multistatus_response('/d:propstat/d:prop/s:foo', xmlns).first.text.should == 'testing'
    end

    it 'should not set properties for a non-existent resource' do
      proppatch(url_root + 'not_found', :input => propset_xml([:foo, 'testing'])).should be_not_found
    end

    it 'should not return properties for non-existent resource' do
      propfind(url_root + 'prop', :input => propfind_xml(:foo)).should be_not_found
    end

    it 'should return the correct charset (utf-8)' do
      put(url_root + 'test.html', :input => '<html/>').should be_created
      propfind(url_root + 'test.html', :input => propfind_xml(:getcontenttype, :getcontentlength))

      charset = @response.media_type_params['charset']
      charset.should eql 'utf-8'
    end

    it 'should not support LOCK' do
      put(url_root + 'test', :input => 'body').should be_created

      xml = render do |xml|
        xml.lockinfo('xmlns:d' => "DAV:") do
          xml.lockscope { xml.exclusive }
          xml.locktype { xml.write }
          xml.owner { xml.href "http://test.de/" }
        end
      end

      lock(url_root + 'test', :input => xml).should be_method_not_allowed
    end

    it 'should not support UNLOCK' do
      put(url_root + 'test', :input => 'body').should be_created
      unlock(url_root + 'test', :input => '').should be_method_not_allowed
    end

  end

  context "Given a not lockable resource" do
    context "when mounted directly" do
      before do
        @controller = RackDAV::Handler.new(
          :root           => DOC_ROOT,
          :resource_class => RackDAV::FileResource
        )
      end

      let(:url_root){ '/' }
      include_examples :not_lockable_resource
    end

    context "When mounted via a URLMap" do
      let(:url_root){ '/dav/' }

      before do
        @controller = Rack::URLMap.new(
          "/dav" => RackDAV::Handler.new(
            :root           => DOC_ROOT,
            :resource_class => RackDAV::FileResource
          )
        )
      end

      include_examples :not_lockable_resource
    end
  end

  private

    def request(method, uri, options={})
      options = {
        'REMOTE_USER' => 'manni'
      }.merge(options)
      request = Rack::MockRequest.new(@controller)
      @response = request.request(method, uri, options)
    end

    METHODS.each do |method|
      define_method(method.downcase) do |*args|
        request(method, *args)
      end
    end


    def render
      Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
        yield xml
      end.to_xml
    end

    def url_escape(string)
      string.gsub(/([^ a-zA-Z0-9_.-]+)/n) do
        '%' + $1.unpack('H2' * $1.size).join('%').upcase
      end.tr(' ', '+')
    end

    def response_xml
      @response_xml ||= Nokogiri::XML(@response.body)
    end

    def response_locktoken
      response_xml.xpath("/d:prop/d:lockdiscovery/d:activelock/d:locktoken/d:href", 'd' => 'DAV:').first.text
    end

    def lockdiscovery_response(token)
      match = lambda do |pattern|
        response_xml.xpath("/d:prop/d:lockdiscovery/d:activelock" + pattern, 'd' => 'DAV:')
      end

      match[''].should_not be_empty

      match['/d:locktype'].should_not be_empty
      match['/d:lockscope'].should_not be_empty
      match['/d:depth'].should_not be_empty
      match['/d:owner'].should_not be_empty
      match['/d:timeout'].should_not be_empty
      match['/d:locktoken/d:href'].should_not be_empty
      match['/d:locktoken/d:href'].first.text.should == token
    end

    def multistatus_response(pattern, ns=nil)
      xmlns = { 'd' => 'DAV:' }
      xmlns.merge!(ns) unless ns.nil?

      @response.should be_multi_status
      response_xml.xpath("/d:multistatus/d:response", xmlns).should_not be_empty
      response_xml.xpath("/d:multistatus/d:response" + pattern, xmlns)
    end

    def propfind_xml(*props)
      render do |xml|
        xml.propfind('xmlns' => "DAV:") do
          xml.prop do
            props.each do |prop, attrs|
              xml.send(prop.to_sym, attrs)
            end
          end
        end
      end
    end

    def propset_xml(*props)
      render do |xml|
        xml.propertyupdate('xmlns' => 'DAV:') do
          xml.set do
            xml.prop do
              props.each do |prop, value, attrs|
                attrs = {} if attrs.nil?
                xml.send(prop.to_sym, value, attrs)
              end
            end
          end
        end
      end
    end
end
