require 'rubygems'
require 'bacon'
require 'mocha'
require 'rack/test'
require 'tempfile'

class Bacon::Context
	include Mocha::Standalone
	include Rack::Test::Methods

	alias_method :old_it, :it
	def it(description)
		old_it(description) do
			mocha_setup
			yield
			mocha_verify
			mocha_teardown
		end
	end
end

require File.dirname(__FILE__) + '/../lib/taps/config'
Taps::Config.taps_database_url = "sqlite://#{Tempfile.new('test.db').path}"
Sequel.connect(Taps::Config.taps_database_url)
