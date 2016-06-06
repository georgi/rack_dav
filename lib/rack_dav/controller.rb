require 'uri'

require_relative 'string'

module RackDAV

  class Controller
    include RackDAV::HTTPStatus

    attr_reader :request, :response, :resource

    def initialize(request, response, options)
      @request  = request
      @response = response
      @options  = options
      @resource = resource_class.new(url_unescape(request.path_info), @request, @response, @options)
      raise Forbidden if request.path_info.include?('../')
    end

    def url_escape(s)
      ::URI.escape(s)
    end

    def url_unescape(s)
      ::Rack::Utils.unescape(s).force_valid_encoding
    end

    def options
      response["Allow"] = 'OPTIONS,HEAD,GET,PUT,POST,DELETE,PROPFIND,PROPPATCH,MKCOL,COPY,MOVE'
      response["Dav"] = "1"

      if resource.lockable?
        response["Allow"] << ",LOCK,UNLOCK"
        response["Dav"]   << ",2"
      end

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
        resource.get
      end
    end

    def put
      raise Forbidden if resource.collection?
      map_exceptions do
        resource.put
      end
      response.status = Created
    end

    def post
      map_exceptions do
        resource.post
      end
    end

    def delete
      raise NotFound if not resource.exist?

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
      # Reject message bodies - RFC2518:8.3.1
      body = @request.body.read(8)
      fail UnsupportedMediaType if !body.nil? && body.length > 0

      map_exceptions do
        resource.make_collection
      end
      response.status = Created
    end

    def copy
      raise NotFound if not resource.exist?

      dest_uri = URI.parse(env['HTTP_DESTINATION'])
      destination = parse_destination(dest_uri)

      raise BadGateway if dest_uri.host and dest_uri.host != request.host
      raise Forbidden if destination == resource.path

      dest = resource_class.new(destination, @request, @response, @options)
      raise PreconditionFailed if dest.exist? && !overwrite

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
      destination = parse_destination(dest_uri)

      raise BadGateway if dest_uri.host and dest_uri.host != request.host
      raise Forbidden if destination == resource.path

      dest = resource_class.new(destination, @request, @response, @options)
      raise PreconditionFailed if dest.exist? && !overwrite

      dest_existed = dest.exist?
      dest = dest.child(resource.name) if dest.collection?

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

      if not request_match("/d:propfind/d:allprop").empty?
        nodes = all_prop_nodes
      else
        nodes = request_match("/d:propfind/d:prop/*")
        nodes = all_prop_nodes if nodes.empty?
      end

      nodes.each do |n|
        # Don't allow empty namespace declarations
        # See litmus props test 3
        raise BadRequest if n.namespace.nil? && n.namespace_definitions.empty?

        # Set a blank namespace if one is included in the request
        # See litmus props test 16
        # <propfind xmlns="DAV:"><prop><nonamespace xmlns=""/></prop></propfind>
        if n.namespace.nil?
          nd = n.namespace_definitions.first
          if nd.prefix.nil? && nd.href.empty?
            n.add_namespace(nil, '')
          end
        end
      end

      multistatus do |xml|
        for resource in find_resources
          resource.path.gsub!(/\/\//, '/')
          xml.response do
            xml.href "http://#{host}#{@request.script_name}#{url_escape resource.path}"
            propstats xml, get_properties(resource, nodes)
          end
        end
      end
    end

    def proppatch
      raise NotFound if not resource.exist?

      nodes = request_match("/d:propertyupdate[d:remove/d:prop/* or d:set/d:prop/*]//d:prop/*")

      # Set a blank namespace if one is included in the request
      # See litmus props test 15
      # <propertyupdate xmlns="DAV:"><set>
      #   <prop><nonamespace xmlns="">randomvalue</nonamespace></prop>
      # </set></propertyupdate>
      nodes.each do |n|
        nd = n.namespace_definitions.first
        if !nd.nil? && nd.prefix.nil? && nd.href.empty?
          n.add_namespace(nil, '')
        end
      end

      multistatus do |xml|
        for resource in find_resources
          xml.response do
            xml.href "http://#{host}#{@request.script_name}#{resource.path}"
            propstats xml, set_properties(resource, nodes)
          end
        end
      end
    end

    def lock
      raise MethodNotAllowed unless resource.lockable?
      raise NotFound if not resource.exist?

      timeout = request_timeout
      if timeout.nil? || timeout.zero?
        timeout = 60
      end

      if request_document.content.empty?
        refresh_lock timeout
      else
        create_lock timeout
      end
    end

    def unlock
      raise MethodNotAllowed unless resource.lockable?

      locktoken = request_locktoken('LOCK_TOKEN')
      raise BadRequest if locktoken.nil?

      response.status = resource.unlock(locktoken) ? NoContent : Forbidden
    end

    private

      def env
        @request.env
      end

      def host
        @request.host
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
        @request_document ||= if (body = request.body.read).empty?
          Nokogiri::XML::Document.new
        else
          Nokogiri::XML(body, &:strict)
        end

      rescue Nokogiri::XML::SyntaxError, RuntimeError # Nokogiri raise RuntimeError :-(
        raise BadRequest
      end

      def request_match(pattern)
        request_document.xpath(pattern, 'd' => 'DAV:')
      end

      def qualified_node_name(node)
        node.namespace.nil? || node.namespace.prefix.nil? ? node.name : "#{node.namespace.prefix}:#{node.name}"
      end

      def qualified_property_name(node)
        node.namespace.nil? || node.namespace.href == 'DAV:' ? node.name : "{#{node.namespace.href}}#{node.name}"
      end

      def all_prop_nodes
        resource.property_names.map do |n|
          node = Nokogiri::XML::Element.new(n, request_document)
          node.add_namespace(nil, 'DAV:')
          node
        end
      end

      # Quick and dirty parsing of the WEBDAV Timeout header.
      # Refuses infinity, rejects anything but Second- timeouts
      #
      # @return [nil] or [Fixnum]
      #
      # @api internal
      #
      def request_timeout
        timeout = request.env['HTTP_TIMEOUT']
        return if timeout.nil? || timeout.empty?

        timeout = timeout.split /,\s*/
        timeout.reject! {|t| t !~ /^Second-/}
        timeout.first.sub('Second-', '').to_i
      end

      def request_locktoken(header)
        token = request.env["HTTP_#{header}"]
        return if token.nil? || token.empty?
        token.scan /^\(?<?(.+?)>?\)?$/
        return $1
      end

      # Creates a new XML document, yields given block
      # and sets the response.body with the final XML content.
      # The response length is updated accordingly.
      #
      # @return [void]
      #
      # @yield  [xml] Yields the Builder XML instance.
      #
      # @api internal
      #
      def render_xml
        content = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
          yield xml
        end.to_xml
        response.body = [content]
        response["Content-Type"] = 'text/xml; charset=utf-8'
        response["Content-Length"] = Rack::Utils.bytesize(content).to_s
      end

      def multistatus
        render_xml do |xml|
          xml.multistatus('xmlns' => "DAV:") do
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

      def get_properties(resource, nodes)
        stats = Hash.new { |h, k| h[k] = [] }
        for node in nodes
          begin
            map_exceptions do
              stats[OK] << [node, resource.get_property(qualified_property_name(node))]
            end
          rescue Status
            stats[$!] << node
          end
        end
        stats
      end

      def set_properties(resource, nodes)
        stats = Hash.new { |h, k| h[k] = [] }
        for node in nodes
          begin
            map_exceptions do
              stats[OK] << [node, resource.set_property(qualified_property_name(node), node.text)]
            end
          rescue Status
            stats[$!] << node
          end
        end
        stats
      end

      def propstats(xml, stats)
        return if stats.empty?
        for status, props in stats
          xml.propstat do
            xml.prop do
              for node, value in props
                if value.is_a?(Nokogiri::XML::Node)
                  xml.send(qualified_node_name(node).to_sym) do
                    rexml_convert(xml, value)
                  end
                else
                  attrs = {}
                  unless node.namespace.nil?
                    unless node.namespace.prefix.nil?
                      attrs = { "xmlns:#{node.namespace.prefix}" => node.namespace.href }
                    else
                      attrs = { 'xmlns' => node.namespace.href }
                    end
                  end

                  xml.send(qualified_node_name(node).to_sym, value, attrs)
                end
              end
            end
            xml.status "#{request.env['HTTP_VERSION']} #{status.status_line}"
          end
        end
      end

      def create_lock(timeout)
        lockscope = request_match("/d:lockinfo/d:lockscope/d:*").first
        lockscope = lockscope.name if lockscope
        locktype = request_match("/d:lockinfo/d:locktype/d:*").first
        locktype = locktype.name if locktype
        owner = request_match("/d:lockinfo/d:owner/d:href").first
        owner = owner.text if owner
        locktoken = "opaquelocktoken:" + sprintf('%x-%x-%s', Time.now.to_i, Time.now.sec, resource.etag)

        # Quick & Dirty - FIXME: Lock should become a new Class
        # and this dirty parameter passing refactored.
        unless resource.lock(locktoken, timeout, lockscope, locktype, owner)
          raise Forbidden
        end

        response['Lock-Token'] = locktoken

        render_lockdiscovery locktoken, lockscope, locktype, timeout, owner
      end

      def refresh_lock(timeout)
        locktoken = request_locktoken('IF')
        raise BadRequest if locktoken.nil?

        timeout, lockscope, locktype, owner = resource.lock(locktoken, timeout)
        unless lockscope && locktype && timeout
          raise Forbidden
        end

        render_lockdiscovery locktoken, lockscope, locktype, timeout, owner
      end

      # FIXME add multiple locks support
      def render_lockdiscovery(locktoken, lockscope, locktype, timeout, owner)
        render_xml do |xml|
          xml.prop('xmlns' => "DAV:") do
            xml.lockdiscovery do
              render_lock(xml, locktoken, lockscope, locktype, timeout, owner)
            end
          end
        end
      end

      def render_lock(xml, locktoken, lockscope, locktype, timeout, owner)
        xml.activelock do
          xml.lockscope { xml.tag! lockscope }
          xml.locktype { xml.tag! locktype }
          xml.depth 'Infinity'
          if owner
            xml.owner { xml.href owner }
          end
          xml.timeout "Second-#{timeout}"
          xml.locktoken do
            xml.href locktoken
          end
        end
      end

      def rexml_convert(xml, element)
        if element.elements.empty?
          if element.text
            xml.send(element.name.to_sym, element.text, element.attributes)
          else
            xml.send(element.name.to_sym, element.attributes)
          end
        else
          xml.send(element.name.to_sym, element.attributes) do
            element.elements.each do |child|
              rexml_convert(xml, child)
            end
          end
        end
      end

      def parse_destination dest_uri
        destination = url_unescape(dest_uri.path)
        destination.slice!(1..@request.script_name.length) if @request.script_name.length > 0
        destination
      end

  end

end
