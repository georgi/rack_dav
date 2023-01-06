#!/usr/bin/env ruby
require 'rack_dav'

app = Rack::Builder.new do
  use Rack::ShowExceptions
  use Rack::CommonLogger
  use Rack::Reloader
  use Rack::Lint

  run RackDAV::Handler.new(:root => File.expand_path(".", __FILE__))

end.to_app

run app
