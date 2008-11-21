require 'rubygems'
require 'bacon'
require 'mocha'

class Bacon::Context
	include Mocha::Standalone

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
