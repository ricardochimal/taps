require File.dirname(__FILE__) + '/base'
require 'sinatra'
require 'sinatra/test/bacon'

require File.dirname(__FILE__) + '/../lib/taps/server'

require 'pp'

describe Taps::Server do
	before do
		Taps::Config.login = 'taps'
		Taps::Config.password = 'tpass'
		@app = Taps::Server
	end

	it "asks for http basic authentication" do
		get '/'
		status.should == 401
	end
end

