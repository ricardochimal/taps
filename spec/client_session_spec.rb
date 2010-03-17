require File.dirname(__FILE__) + '/base'
require 'taps/client_session'

describe Taps::ClientSession do
	before do
		@client = Taps::ClientSession.new('sqlite://my.db', 'http://example.com:3000', 1000)
		@client.stubs(:session_resource).returns(mock('session resource'))
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

	it "verifies the db version, receive the schema, data, indexes, then reset the sequences" do
		@client.expects(:verify_server)
		@client.expects(:pull_schema)
		@client.expects(:pull_data)
		@client.expects(:pull_indexes)
		@client.expects(:pull_reset_sequences)
		@client.pull.should.be.nil
	end

	it "checks the version of the server by seeing if it has access" do
		@client.stubs(:server).returns(mock('server'))
		@request = mock('request')
		@client.server.expects(:[]).with('/').returns(@request)
		@request.expects(:get).with({:taps_version => Taps.compatible_version})

		lambda { @client.verify_server }.should.not.raise
	end

	it "fetches remote tables info from taps server" do
		@res = mock("rest-client response")
		@marshal_data = Marshal.dump({ :mytable => 2 })
		@res.stubs(:body).returns(@marshal_data)
		@client.session_resource.stubs(:[]).with('pull/tables').returns(mock('tables'))
		@client.session_resource['pull/tables'].stubs(:get).with(:taps_version => Taps.compatible_version).returns(@res)
		@client.fetch_remote_tables_info.should == [ { :mytable => 2 }, 2 ]
	end

	it "hides the password in urls" do
		@client.safe_url("postgres://postgres:password@localhost/mydb").should == "postgres://postgres:[hidden]@localhost/mydb"
		@client.safe_url("postgres://postgres@localhost/mydb").should == "postgres://postgres@localhost/mydb"
		@client.safe_url("http://x:y@localhost:5000").should == "http://x:[hidden]@localhost:5000"
	end
end

