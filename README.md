RackDAV - Web Authoring for Rack and Rails
==========================================

RackDAV is Handler for [Rack][1], which allows content authoring over
HTTP. RackDAV brings its own implentation for authoring files, but
other resource types are possible by subclassing RackDAV::Resource.

## Install

Just install the gem from github:

    $ gem sources -a http://gems.github.com
    $ sudo gem install georgi-rack_dav

## Quickstart

If you just want to share a folder over WebDAV, you can just start a
simple server with this:

    $ rack_dav

This will start a WEBrick server on port 3000, which you can connect
to withou authentication.

## Rack Handler

Using RackDAV inside a rack application is quite easy. A simple rackup
script looks like this:

    require 'rubygems'
    require 'rack_dav'
     
    use Rack::CommonLogger
     
    run RackDAV::Handler.new('/path/to/docs')

## Implementing your own WebDAV resource

You have to subclass RackDAV::Resource and implement following
methods:
        
* _children_: If this is a collection, return the child resources.

* _collection?_: Is this resource a collection?

* _exist?; end_: Does this recource exist?
    
* _creation\_date: Return the creation time.

* _last_modified: Return the time of last modification.
    
* _last_modified=(time): Set the time of last modification.

* _etag_: Return an Etag, an unique hash value for this resource.

* _content_type_: Return the mime type of this resource.

* _content\_length_: Return the size in bytes for this resource.

* _get(request, response)_: Write the content of the resource to the response.body.

* _put(request, response)_: Save the content of the request.body.

* _post(request, response)_: Usually forbidden.

* _delete_: Delete this resource.

* _copy(dest)_: Copy this resource to given destination resource.

* _move(dest)_: Move this resource to given destination resource.
    
* _make\_collection_: Create this resource as collection.


Each resource has a path attribute, which you must use to find and
manipulate the real resource.

Finally you have to tell RackDAV::Handler, what class it should use:

    RackDAV::Handler.new(:resource_class => MyResource)


### RackDAV on GitHub

Download or fork the project on its [Github page][2]


[1]: http://github.com/chneukirchen/rack
[2]: http://github.com/georgi/rack_dav
