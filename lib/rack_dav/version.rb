module RackDAV

  # Holds information about library version.
  module Version
    MAJOR = 0
    MINOR = 3
    PATCH = 0
    BUILD = nil

    STRING = [MAJOR, MINOR, PATCH, BUILD].compact.join(".")
  end

  # The current library version.
  VERSION = Version::STRING

end
