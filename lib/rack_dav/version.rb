module RackDAV

  # Holds information about library version.
  module Version
    MAJOR = 0
    MINOR = 2
    PATCH = "dev"
    BUILD = nil

    STRING = [MAJOR, MINOR, PATCH, BUILD].compact.join(".")
  end

  # The current library version.
  VERSION = Version::STRING

end