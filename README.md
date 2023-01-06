---
RackDAV - Web Authoring for Rack
---

RackDAV is a Ruby gem that allows you to use the WebDAV protocol to edit and manage files over HTTP. It comes with its own file backend, but you can also create your own backend by subclassing RackDAV::Resource.

## Quickstart

To install the gem, run `gem install rack_dav`.

To quickly test out RackDAV, copy the config.ru file from this repository and run `bundle exec rackup`. This will start a web server on a default port that you can connect to without any authentication.

## Rack Handler

To use RackDAV in your own rack application, include the following in your config.ru file:

    require 'rubygems'
    require 'rack_dav'

    use Rack::CommonLogger

    run RackDAV::Handler.new(:root => '/path/to/docs')

## Implementing your own WebDAV resource

If you want to create your own WebDAV resource, you will need to subclass RackDAV::Resource and implement the following methods:

* __children__: If this is a collection, return the child resources.

* __collection?__: Is this resource a collection?

* __exist?__: Does this recource exist?

* __creation\_date__: Return the creation time.

* __last\_modified__: Return the time of last modification.

* __last\_modified=(time)__: Set the time of last modification.

* __etag__: Return an Etag, an unique hash value for this resource.

* __content_type__: Return the mime type of this resource.

* __content\_length__: Return the size in bytes for this resource.

* __get(request, response)__: Write the content of the resource to the response.body.

* __put(request, response)__: Save the content of the request.body.

* __post(request, response)__: Usually forbidden.

* __delete__: Delete this resource.

* __copy(dest)__: Copy this resource to given destination resource.

* __move(dest)__: Move this resource to given destination resource.

* __make\_collection__: Create this resource as collection.

* __set_custom_property(name, value)__: Set a custom property on the resource. If the value is nil, delete the custom property.

* __get_custom_property(name)__: Return the value of the named custom property.

* __lock(locktoken, timeout, lockscope=nil, locktype=nil, owner=nil)__: Lock this resource.
  If scope, type and owner are nil, refresh the given lock.

* __unlock(token)__: Unlock this resource

Note that it is possible that a resource object may be instantiated for a resource that does not yet exist.

For more examples and inspiration, you can look at the FileResource implementation.
