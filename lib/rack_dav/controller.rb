module RackDAV
  
  class Controller
    include RackDAV::HTTPStatus
    
    attr_reader :request, :response, :resource
    
    def initialize(request, response, options)
      @request = request
      @response = response
      @options = options
      @resource = resource_class.new(url_unescape(request.path_info), @options)
      raise Forbidden if request.path_info.include?('..')
    end
    
    def url_escape(s)
      s.gsub(/([^\/a-zA-Z0-9_.-]+)/n) do
        '%' + $1.unpack('H2' * $1.size).join('%').upcase
      end.tr(' ', '+')
    end

    def url_unescape(s)
      s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) do
        [$1.delete('%')].pack('H*')
      end
    end    
    
    def options
      response["Allow"] = 'OPTIONS,HEAD,GET,PUT,POST,DELETE,PROPFIND,PROPPATCH,MKCOL,COPY,MOVE,LOCK,UNLOCK'
      response["Dav"] = "1"
      response["Ms-Author-Via"] = "DAV"
    end
    
    def head
      raise NotFound if not resource.exist?
      response['Etag'] = resource.etag
      response['Content-Type'] = resource.content_type
      response['Content-Length'] = resource.content_length.to_s
      response['Last-Modified'] = resource.last_modified.httpdate
    end
    
    def get
      raise NotFound if not resource.exist?
      response['Etag'] = resource.etag
      response['Content-Type'] = resource.content_type
      response['Content-Length'] = resource.content_length.to_s
      response['Last-Modified'] = resource.last_modified.httpdate      
      map_exceptions do
        resource.get(request, response)
      end
    end

    def put
      raise Forbidden if resource.collection?
      map_exceptions do
        resource.put(request, response)
      end
    end

    def post
      map_exceptions do
        resource.post(request, response)
      end
    end

    def delete
      delete_recursive(resource, errors = [])
      
      if errors.empty?
        response.status = NoContent
      else
        multistatus do |xml|
          response_errors(xml, errors)
        end
      end
    end
    
    def mkcol
      map_exceptions do
        resource.make_collection
      end
      response.status = Created
    end
    
    def copy
      raise NotFound if not resource.exist?
      
      dest_uri = URI.parse(env['HTTP_DESTINATION'])
      destination = url_unescape(dest_uri.path)

      raise BadGateway if dest_uri.host and dest_uri.host != request.host
      raise Forbidden if destination == resource.path
      
      dest = resource_class.new(destination, @options)
      dest = dest.child(resource.name) if dest.collection?
      
      dest_existed = dest.exist?
      
      copy_recursive(resource, dest, depth, errors = [])
      
      if errors.empty?
        response.status = dest_existed ? NoContent : Created
      else
        multistatus do |xml|
          response_errors(xml, errors)
        end
      end
    rescue URI::InvalidURIError => e
      raise BadRequest.new(e.message)
    end

    def move
      raise NotFound if not resource.exist?

      dest_uri = URI.parse(env['HTTP_DESTINATION'])
      destination = url_unescape(dest_uri.path)
      
      raise BadGateway if dest_uri.host and dest_uri.host != request.host
      raise Forbidden if destination == resource.path
      
      dest = resource_class.new(destination, @options)
      dest = dest.child(resource.name) if dest.collection?
      
      dest_existed = dest.exist?
      
      raise Conflict if depth <= 1
      
      copy_recursive(resource, dest, depth, errors = [])
      delete_recursive(resource, errors)
      
      if errors.empty?
        response.status = dest_existed ? NoContent : Created
      else
        multistatus do |xml|
          response_errors(xml, errors)
        end
      end
    rescue URI::InvalidURIError => e
      raise BadRequest.new(e.message)
    end
    
    def propfind
      raise NotFound if not resource.exist?

      if not request_match("/propfind/allprop").empty?
        names = resource.property_names
      else
        names = request_match("/propfind/prop/*").map { |e| e.name }
        raise BadRequest if names.empty?
      end

      multistatus do |xml|
        for resource in find_resources
          xml.response do
            xml.href "http://#{host}#{url_escape resource.path}"
            propstats xml, get_properties(resource, names)
          end
        end
      end
    end
    
    def proppatch
      raise NotFound if not resource.exist?

      prop_rem = request_match("/propertyupdate/remove/prop/*").map { |e| [e.name] }
      prop_set = request_match("/propertyupdate/set/prop/*").map { |e| [e.name, e.text] }

      multistatus do |xml|
        for resource in find_resources
          xml.response do
            xml.href "http://#{host}#{resource.path}"
            propstats xml, set_properties(resource, prop_set)
          end
        end
      end

      resource.save
    end

    def lock
      raise NotFound if not resource.exist?

      lockscope = request_match("/lockinfo/lockscope/*")[0].name
      locktype = request_match("/lockinfo/locktype/*")[0].name
      owner = request_match("/lockinfo/owner/href")[0]
      locktoken = "opaquelocktoken:" + sprintf('%x-%x', object_id.abs, Time.now.to_i)

      response['Lock-Token'] = locktoken

      render_xml do |xml|
        xml.prop('xmlns:D' => "DAV:") do
          xml.lockdiscovery do
            xml.activelock do
              xml.lockscope { xml.tag! lockscope }
              xml.locktype { xml.tag! locktype }
              xml.depth 'Infinity'
              if owner
                xml.owner { xml.href owner.text }
              end
              xml.timeout "Second-60"
              xml.locktoken do
                xml.href locktoken
              end
            end
          end
        end
      end
    end

    def unlock
      raise NoContent
    end

    # ************************************************************
    # private methods
    
    private

    def env
      @request.env
    end
    
    def host
      env['HTTP_HOST']
    end
    
    def resource_class
      @options[:resource_class]
    end

    def depth
      case env['HTTP_DEPTH']
      when '0' then 0
      when '1' then 1
      else 100
      end
    end

    def overwrite
      env['HTTP_OVERWRITE'].to_s.upcase != 'F'
    end

    def find_resources
      case env['HTTP_DEPTH']
      when '0'
        [resource]
      when '1'
        [resource] + resource.children
      else
        [resource] + resource.descendants
      end
    end

    def delete_recursive(res, errors)
      for child in res.children
        delete_recursive(child, errors)
      end
      
      begin
        map_exceptions { res.delete } if errors.empty?
      rescue Status
        errors << [res.path, $!]
      end
    end
    
    def copy_recursive(res, dest, depth, errors)
      map_exceptions do
        if dest.exist?
          if overwrite
            delete_recursive(dest, errors)
          else
            raise PreconditionFailed
          end
        end
        res.copy(dest)
      end
    rescue Status
      errors << [res.path, $!]
    else
      if depth > 0
        for child in res.children
          dest_child = dest.child(child.name)
          copy_recursive(child, dest_child, depth - 1, errors)
        end
      end
    end
    
    def map_exceptions
      yield
    rescue
      case $!
      when URI::InvalidURIError then raise BadRequest
      when Errno::EACCES then raise Forbidden
      when Errno::ENOENT then raise Conflict
      when Errno::EEXIST then raise Conflict      
      when Errno::ENOSPC then raise InsufficientStorage
      else
        raise
      end
    end
    
    def request_document
      @request_document ||= REXML::Document.new(request.body.read)
    rescue REXML::ParseException
      raise BadRequest
    end

    def request_match(pattern)
      REXML::XPath::match(request_document, pattern, '' => 'DAV:')
    end

    def render_xml
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
      
      xml.namespace('D') do
        yield xml
      end
      
      response.body = xml.target!
      response["Content-Type"] = 'text/xml; charset="utf-8"'
      response["Content-Length"] = response.body.size.to_s
    end
      
    def multistatus
      render_xml do |xml|
        xml.multistatus('xmlns:D' => "DAV:") do
          yield xml
        end
      end
      
      response.status = MultiStatus
    end
    
    def response_errors(xml, errors)
      for path, status in errors
        xml.response do
          xml.href "http://#{host}#{path}"
          xml.status "#{request.env['HTTP_VERSION']} #{status.status_line}"
        end
      end
    end

    def get_properties(resource, names)
      stats = Hash.new { |h, k| h[k] = [] }
      for name in names
        begin
          map_exceptions do
            stats[OK] << [name, resource.get_property(name)]
          end
        rescue Status
          stats[$!] << name
        end
      end
      stats
    end

    def set_properties(resource, pairs)
      stats = Hash.new { |h, k| h[k] = [] }
      for name, value in pairs
        begin
          map_exceptions do
            stats[OK] << [name, resource.set_property(name, value)]
          end
        rescue Status
          stats[$!] << name
        end
      end
      stats
    end
    
    def propstats(xml, stats)
      return if stats.empty?
      for status, props in stats
        xml.propstat do
          xml.prop do
            for name, value in props
              if value.is_a?(REXML::Element)
                xml.tag!(name) do
                  rexml_convert(xml, value)
                end
              else
                xml.tag!(name, value)
              end
            end
          end
          xml.status "#{request.env['HTTP_VERSION']} #{status.status_line}"
        end
      end
    end
    
    def rexml_convert(xml, element)
      if element.elements.empty?
        if element.text
          xml.tag!(element.name, element.text, element.attributes)
        else
          xml.tag!(element.name, element.attributes)
        end
      else
        xml.tag!(element.name, element.attributes) do
          element.elements.each do |child|
            rexml_convert(xml, child)
          end
        end
      end
    end
    
  end

end 
