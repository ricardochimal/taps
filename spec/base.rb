require 'rubygems'
require 'bacon'
require 'mocha'
require 'mocha/api'
require 'rack/test'
require 'tempfile'

$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

class Bacon::Context
  include Mocha::API
  include Rack::Test::Methods

  alias old_it it
  def it(description)
    old_it(description) do
      mocha_setup
      yield
      mocha_verify
      mocha_teardown
    end
  end
end

require 'taps/config'
Taps::Config.taps_database_url = "sqlite://#{Tempfile.new('test.db').path}"
Sequel.connect(Taps::Config.taps_database_url)
