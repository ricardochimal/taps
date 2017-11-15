module Taps
  module Version
    MAJOR = 0
    MINOR = 6
    PATCH = 3
    BUILD = 0

    def self.current
      version = "#{MAJOR}.#{MINOR}.#{PATCH}"
      version += ".#{BUILD}" if BUILD > 0
      version
    end

    def self.compatible_version
      "#{MAJOR}.#{MINOR}"
    end
  end
end
