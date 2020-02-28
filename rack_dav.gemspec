# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rack_dav/version"

Gem::Specification.new do |s|
  s.name          = "rack_dav"
  s.version       = RackDAV::VERSION
  s.author        = "Matthias Georgi"
  s.email         = "matti.georgi@gmail.com"
  s.homepage      = "http://georgi.github.com/rack_dav"
  s.summary       = "WebDAV handler for Rack."
  s.description   = "WebDAV handler for Rack."
  s.license       = "MIT"

  s.files         = `git ls-files`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.extra_rdoc_files = ["README.md"]

  s.add_dependency("rack", "~> 1.4")
  s.add_dependency('nokogiri', "~> 1.5")
  s.add_dependency("ffi-xattr", "~> 0.1")
  s.add_development_dependency("rspec", "~> 2.11")
  s.add_development_dependency("rake","~> 13.0")
end
