require 'rspec'
require 'rack_dav'

unless defined?(SPEC_ROOT)
  SPEC_ROOT = File.expand_path("../", __FILE__)
end

RSpec.configure do |config|
end
