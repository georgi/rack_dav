module RackDAV
  
  class Handler
    
    def initialize(options={})
      @options = {
        :resource_class => FileResource,
        :root => Dir.pwd
      }.merge(options)
    end

    def call(env)
      request = Rack::Request.new(env)
      response = Rack::Response.new

      begin
        controller = Controller.new(request, response, @options.dup)
        controller.send(request.request_method.downcase)
        
      rescue HTTPStatus::Status => status
        response.status = status.code
        response.body = status.message if status.code >= 300
        unless status.code < 200 or [204, 304].include?(status.code)
          response['Content-Length'] = response.body.size.to_s
        end
      end

      response.status = response.status ? response.status.to_i : 200
      response.finish
    end
    
  end

end
