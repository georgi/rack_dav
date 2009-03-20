$:.unshift(File.expand_path(File.dirname(__FILE__) + '/../lib'))

require 'rubygems'
require 'rack_dav'
require 'fileutils'

describe RackDAV::Handler do
  DOC_ROOT = File.expand_path(File.dirname(__FILE__) + '/htdocs')
  METHODS = %w(GET PUT POST DELETE PROPFIND PROPPATCH MKCOL COPY MOVE OPTIONS HEAD)  
  
  before do
    FileUtils.mkdir(DOC_ROOT) unless File.exists?(DOC_ROOT)
    @controller = RackDAV::Handler.new(:root => DOC_ROOT)
  end

  after do
    FileUtils.rm_rf(DOC_ROOT) if File.exists?(DOC_ROOT)
  end
  
  attr_reader :response
  
  def request(method, uri, options={})
    options = {
      'HTTP_HOST' => 'localhost',
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
    xml = Builder::XmlMarkup.new
    xml.instruct! :xml, :version => "1.0", :encoding => "UTF-8"      
    xml.namespace('d') do
      yield xml
    end
    xml.target!
  end

  def url_escape(string)
    string.gsub(/([^ a-zA-Z0-9_.-]+)/n) do
      '%' + $1.unpack('H2' * $1.size).join('%').upcase
    end.tr(' ', '+')
  end
  
  def response_xml
    REXML::Document.new(@response.body)
  end
  
  def multistatus_response(pattern)
    @response.should be_multi_status
    REXML::XPath::match(response_xml, "/multistatus/response", '' => 'DAV:').should_not be_empty
    REXML::XPath::match(response_xml, "/multistatus/response" + pattern, '' => 'DAV:')
  end

  def propfind_xml(*props)
    render do |xml|
      xml.propfind('xmlns:d' => "DAV:") do
        xml.prop do
          props.each do |prop|
          xml.tag! prop
          end
        end
      end
    end
  end
  
  it 'should return all options' do
    options('/').should be_ok
    
    METHODS.each do |method|
      response.headers['allow'].should include(method)
    end
  end
  
  it 'should return headers' do
    put('/test.html', :input => '<html/>').should be_ok
    head('/test.html').should be_ok
    
    response.headers['etag'].should_not be_nil
    response.headers['content-type'].should match(/html/)
    response.headers['last-modified'].should_not be_nil
  end
  
  it 'should not find a nonexistent resource' do
    get('/not_found').should be_not_found
  end
  
  it 'should not allow directory traversal' do
    get('/../htdocs').should be_forbidden
  end
  
  it 'should create a resource and allow its retrieval' do
    put('/test', :input => 'body').should be_ok    
    get('/test').should be_ok
    response.body.should eql('body')
  end
  it 'should create and find a url with escaped characters' do
    put(url_escape('/a b'), :input => 'body').should be_ok    
    get(url_escape('/a b')).should be_ok
    response.body.should eql('body')
  end
  
  it 'should delete a single resource' do
    put('/test', :input => 'body').should be_ok
    delete('/test').should be_no_content
  end
  
  it 'should delete recursively' do
    mkcol('/folder').should be_created
    put('/folder/a', :input => 'body').should be_ok
    put('/folder/b', :input => 'body').should be_ok
    
    delete('/folder').should be_no_content
    get('/folder').should be_not_found
    get('/folder/a').should be_not_found
    get('/folder/b').should be_not_found
  end

  it 'should not allow copy to another domain' do
    put('/test', :input => 'body').should be_ok
    copy('http://localhost/', 'HTTP_DESTINATION' => 'http://another/').should be_bad_gateway
  end

  it 'should not allow copy to the same resource' do
    put('/test', :input => 'body').should be_ok
    copy('/test', 'HTTP_DESTINATION' => '/test').should be_forbidden
  end

  it 'should not allow an invalid destination uri' do
    put('/test', :input => 'body').should be_ok
    copy('/test', 'HTTP_DESTINATION' => '%').should be_bad_request
  end

  it 'should copy a single resource' do
    put('/test', :input => 'body').should be_ok
    copy('/test', 'HTTP_DESTINATION' => '/copy').should be_created
    get('/copy').body.should eql('body')
  end

  it 'should copy a resource with escaped characters' do
    put(url_escape('/a b'), :input => 'body').should be_ok
    copy(url_escape('/a b'), 'HTTP_DESTINATION' => url_escape('/a c')).should be_created
    get(url_escape('/a c')).should be_ok
    response.body.should eql('body')
  end
  
  it 'should deny a copy without overwrite' do
    put('/test', :input => 'body').should be_ok
    put('/copy', :input => 'copy').should be_ok
    copy('/test', 'HTTP_DESTINATION' => '/copy', 'HTTP_OVERWRITE' => 'F')    
    multistatus_response('/href').first.text.should eql('http://localhost/test')
    multistatus_response('/status').first.text.should match(/412 Precondition Failed/)
    get('/copy').body.should eql('copy')
  end
  
  it 'should allow a copy with overwrite' do
    put('/test', :input => 'body').should be_ok
    put('/copy', :input => 'copy').should be_ok
    copy('/test', 'HTTP_DESTINATION' => '/copy', 'HTTP_OVERWRITE' => 'T').should be_no_content
    get('/copy').body.should eql('body')
  end
  
  it 'should copy a collection' do
    mkcol('/folder').should be_created
    copy('/folder', 'HTTP_DESTINATION' => '/copy').should be_created
    propfind('/copy', :input => propfind_xml(:resourcetype))
    multistatus_response('/propstat/prop/resourcetype/collection').should_not be_empty
  end

  it 'should copy a collection resursively' do
    mkcol('/folder').should be_created
    put('/folder/a', :input => 'A').should be_ok
    put('/folder/b', :input => 'B').should be_ok
    
    copy('/folder', 'HTTP_DESTINATION' => '/copy').should be_created
    propfind('/copy', :input => propfind_xml(:resourcetype))
    multistatus_response('/propstat/prop/resourcetype/collection').should_not be_empty    
    
    get('/copy/a').body.should eql('A')
    get('/copy/b').body.should eql('B')
  end
  
  it 'should move a collection recursively' do
    mkcol('/folder').should be_created
    put('/folder/a', :input => 'A').should be_ok
    put('/folder/b', :input => 'B').should be_ok
    
    move('/folder', 'HTTP_DESTINATION' => '/move').should be_created
    propfind('/move', :input => propfind_xml(:resourcetype))
    multistatus_response('/propstat/prop/resourcetype/collection').should_not be_empty    
    
    get('/move/a').body.should eql('A')
    get('/move/b').body.should eql('B')
    get('/folder/a').should be_not_found
    get('/folder/b').should be_not_found
  end
  
  it 'should create a collection' do
    mkcol('/folder').should be_created
    propfind('/folder', :input => propfind_xml(:resourcetype))
    multistatus_response('/propstat/prop/resourcetype/collection').should_not be_empty
  end
  
  it 'should not find properties for nonexistent resources' do
    propfind('/non').should be_conflict
  end
  
  it 'should find all properties' do
    xml = render do |xml|
      xml.propfind('xmlns:d' => "DAV:") do
        xml.allprop
      end
    end
    
    propfind('http://localhost/', :input => xml)
    
    multistatus_response('/href').first.text.strip.should eql('http://localhost/')

    props = %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength)
    props.each do |prop|
      multistatus_response('/propstat/prop/' + prop).should_not be_empty
    end
  end
  
  it 'should find named properties' do
    put('/test.html', :input => '<html/>').should be_ok    
    propfind('/test.html', :input => propfind_xml(:getcontenttype, :getcontentlength))
   
    multistatus_response('/propstat/prop/getcontenttype').first.text.should eql('text/html')
    multistatus_response('/propstat/prop/getcontentlength').first.text.should eql('7')
  end

end
