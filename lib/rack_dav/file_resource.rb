module RackDAV

  class FileResource < Resource
    include WEBrick::HTTPUtils
    
    # If this is a collection, return the child resources.
    def children
      Dir[file_path + '/*'].map do |path|
        child File.basename(path)
      end
    end

    # Is this resource a collection?
    def collection?
      File.directory?(file_path)
    end

    # Does this recource exist?
    def exist?
      File.exist?(file_path)
    end
    
    # Return the creation time.
    def creation_date
      stat.ctime
    end

    # Return the time of last modification.
    def last_modified
      stat.mtime
    end
    
    # Set the time of last modification.
    def last_modified=(time)
      File.utime(Time.now, time, file_path)
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
      sprintf('%x-%x-%x', stat.ino, stat.size, stat.mtime.to_i)
    end

    # Return the resource type.
    #
    # If this is a collection, return
    # REXML::Element.new('D:collection')
    def resource_type
      if collection?
        REXML::Element.new('D:collection')
      end
    end

    # Return the mime type of this resource.
    def content_type
      if stat.directory?
        "text/html"
      else 
        mime_type(file_path, DefaultMimeTypes)
      end
    end

    # Return the size in bytes for this resource.
    def content_length
      stat.size
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get(request, response)
      if stat.directory?
        response.body = ""
        Rack::Directory.new(root).call(request.env)[2].each do |line|
          response.body << line
        end
        response['Content-Length'] = response.body.size.to_s
      else
        file = Rack::File.new(nil)
        file.path = file_path
        response.body = file
      end
    end

    # HTTP PUT request.
    #
    # Save the content of the request.body.
    def put(request, response)
      write(request.body)
    end
    
    # HTTP POST request.
    #
    # Usually forbidden.
    def post(request, response)
      raise HTTPStatus::Forbidden
    end
    
    # HTTP DELETE request.
    #
    # Delete this resource.
    def delete
      if stat.directory?
        Dir.rmdir(file_path)
      else
        File.unlink(file_path)
      end
    end
    
    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest)
      if stat.directory?
        dest.make_collection
      else
        open(file_path, "rb") do |file|
          dest.write(file)
        end
      end
    end
  
    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(dest)
      copy(dest)
      delete
    end
    
    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
      Dir.mkdir(file_path)
    end
  
    # Write to this resource from given IO.
    def write(io)
      tempfile = "#{file_path}.#{Process.pid}.#{object_id}"
      
      open(tempfile, "wb") do |file|
        while part = io.read(8192)
          file << part
        end
      end

      File.rename(tempfile, file_path)      
    ensure
      File.unlink(tempfile) rescue nil
    end
    
    private

    def root
      @options[:root]
    end

    def file_path
      root + '/' + path
    end

    def stat
      @stat ||= File.stat(file_path)
    end

  end

end
