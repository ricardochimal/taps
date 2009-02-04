require File.dirname(__FILE__) + '/base'
require File.dirname(__FILE__) + '/../lib/taps/client_session'

describe Taps::ClientSession do
	before do
		@client = Taps::ClientSession.new('sqlite://my.db', 'http://example.com:3000', 1000)
	end

	it "starts a session and yields the session object to the block" do
		Taps::ClientSession.start('x', 'y', 1000) do |session|
			session.database_url.should == 'x'
			session.remote_url.should == 'y'
			session.default_chunksize.should == 1000
		end
	end

	it "opens the local db connection via sequel and the database url" do
		Sequel.expects(:connect).with('sqlite://my.db').returns(:con)
		@client.db.should == :con
	end

	it "creates a restclient resource to the remote server" do
		@client.server.url.should == 'http://example.com:3000'
	end
end

