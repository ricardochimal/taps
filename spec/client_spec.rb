require File.dirname(__FILE__) + '/base'
require File.dirname(__FILE__) + '/../lib/taps/client'

describe Taps::Client do
	before do
		@client = Taps::Client.new('sqlite://my.db', 'http://example.com:3000')
	end

	it "opens the local db connection via sequel and the database url" do
		Sequel.expects(:connect).with('sqlite://my.db').returns(:con)
		@client.db.should.equal :con
	end

	it "creates a restclient resource to the remote server" do
		@client.server.url.should.equal 'http://example.com:3000'
	end
end

