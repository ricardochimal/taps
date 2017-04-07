$:.unshift File.expand_path("../lib", __FILE__)
require "taps/version"

Gem::Specification.new do |gem|
  gem.name        = "taps2"
  gem.version     = Taps.version
  gem.author      = ["Ricardo Chimal, Jr.", "Joel Van Horn"]
  gem.email       = ["ricardo@heroku.com", "joel@joelvanhorn.com"]
  gem.homepage    = "http://github.com/joelvh/taps2"
  gem.summary     = "Simple database import/export app"
  gem.description = "A simple database agnostic import/export app to transfer data to/from a remote database."
  gem.executables = %w( taps schema )

  gem.files = Dir["**/*"].select { |d| d =~ %r{^(README|VERSION|bin/|data/|ext/|lib/|spec/|test/)} }

  gem.add_runtime_dependency "rack",        ">= 1.0.1"
  gem.add_runtime_dependency "rest-client", ">= 1.4.0"
  gem.add_runtime_dependency "sequel",      ">= 4.0.0"
  gem.add_runtime_dependency "sinatra",     ">= 1.4.4"
  gem.add_runtime_dependency "sqlite3",     ">= 1.3.8"
  gem.add_runtime_dependency "extlib"

  gem.add_development_dependency "bacon"
  gem.add_development_dependency "mocha", ">= 1.2.1"
  gem.add_development_dependency "rack-test"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "simplecov"
end
