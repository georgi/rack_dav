---
RackDAV - Web Authoring for Rack
---

RackDAV is Handler for [Rack][1], which allows content authoring over
HTTP. RackDAV brings its own file backend, but other backends are
possible by subclassing RackDAV::Resource.

## Install

Just install the gem from RubyGems:

    $ gem install rack_dav

## Quickstart

If you just want to share a folder over WebDAV, you can just start a
simple server with:

    $ rack_dav

This will start a WEBrick server on port 3000, which you can connect
to without authentication.

## Rack Handler

Using RackDAV inside a rack application is quite easy. A simple rackup
script looks like this:

    require 'rubygems'
    require 'rack_dav'
    
    use Rack::CommonLogger
    
    run RackDAV::Handler.new(:root => '/path/to/docs')

## Implementing your own WebDAV resource

RackDAV::Resource is an abstract base class and defines an interface
for accessing resources.

Each resource will be initialized with a path, which should be used to
find the real resource.

RackDAV::Handler needs to be initialized with the actual resource class:

    RackDAV::Handler.new(:resource_class => MyResource)

RackDAV needs some information about the resources, so you have to
implement following methods:

* __children__: If this is a collection, return the child resources.

* __collection?__: Is this resource a collection?

* __exist?__: Does this recource exist?

* __creation\_date__: Return the creation time.

* __last\_modified__: Return the time of last modification.

* __last\_modified=(time)__: Set the time of last modification.

* __etag__: Return an Etag, an unique hash value for this resource.

* __content_type__: Return the mime type of this resource.

* __content\_length__: Return the size in bytes for this resource.


Most importantly you have to implement the actions, which are called
to retrieve and change the resources:

* __get(request, response)__: Write the content of the resource to the response.body.

* __put(request, response)__: Save the content of the request.body.

* __post(request, response)__: Usually forbidden.

* __delete__: Delete this resource.

* __copy(dest)__: Copy this resource to given destination resource.

* __move(dest)__: Move this resource to given destination resource.

* __make\_collection__: Create this resource as collection.

* __lock(locktoken, timeout, lockscope=nil, locktype=nil, owner=nil)__: Lock this resource.
  If scope, type and owner are nil, refresh the given lock.

* __unlock(token)__: Unlock this resource

Note, that it is generally possible, that a resource object is
instantiated for a not yet existing resource.

For inspiration you should have a look at the FileResource
implementation. Please let me now, if you are going to implement a new
type of resource.


### RackDAV on GitHub

Download or fork the project on its [Github page][2]


[1]: http://github.com/chneukirchen/rack
[2]: http://github.com/georgi/rack_dav
