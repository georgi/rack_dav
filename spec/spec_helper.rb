require 'rspec'
require 'rack_dav'

unless defined?(SPEC_ROOT)
  SPEC_ROOT = File.expand_path("../", __FILE__)
end

module Helpers

  private

    # Gets the currently described class.
    # Conversely to +subject+, it returns the class
    # instead of an instance.
    def klass
      described_class
    end

end

RSpec.configure do |config|
  config.include Helpers
end
