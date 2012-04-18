$:.unshift File.expand_path("../lib", __FILE__)
require "taps/version"

Gem::Specification.new do |gem|
  gem.name        = "taps"
  gem.version     = Taps.version
  gem.author      = "Ricardo Chimal, Jr."
  gem.email       = "ricardo@heroku.com"
  gem.homepage    = "http://github.com/ricardochimal/taps"
  gem.summary     = "simple database import/export app"
  gem.description = "A simple database agnostic import/export app to transfer data to/from a remote database."
  gem.executables = %w( taps schema )

  gem.files = Dir["**/*"].select { |d| d =~ %r{^(README|VERSION|bin/|data/|ext/|lib/|spec/|test/)} }

  gem.add_dependency "rack"
  gem.add_dependency "rest-client"
  gem.add_dependency "sequel"
  gem.add_dependency "sinatra"
  gem.add_dependency "sqlite3-ruby"

  gem.add_development_dependency "bacon"
  gem.add_development_dependency "mocha"
  gem.add_development_dependency "rack-test"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "rcov"
end

