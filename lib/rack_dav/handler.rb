module RackDAV

  class Handler

    # @return [Hash] The hash of options.
    attr_reader :options


    ALLOWED_METHODS = %w(GET PUT POST DELETE PROPFIND PROPPATCH MKCOL COPY MOVE OPTIONS HEAD LOCK UNLOCK)


    # Initializes a new instance with given options.
    #
    # @param  [Hash] options Hash of options to customize the handler behavior.
    # @option options [Class] :resource_class (FileResource)
    #         The resource class.
    # @option options [String] :root (".")
    #         The root resource folder.
    #
    def initialize(options = {})
      @options = {
        :resource_class => FileResource,
        :root => Dir.pwd
      }.merge(options)
    end

    def call(env)
      request  = Rack::Request.new(env)
      response = Rack::Response.new

      begin
        controller = Controller.new(request, response, @options)
        if ALLOWED_METHODS.include?(request.request_method)
          controller.send(request.request_method.downcase)
        else
          response.status = 405
          response['Allow'] = ALLOWED_METHODS.join(', ')
        end

      rescue HTTPStatus::Status => status
        response.status = status.code
      end

      response.finish
    end

  end

end
