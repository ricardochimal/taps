require File.dirname(__FILE__) + '/base'
require File.dirname(__FILE__) + '/../lib/taps/client_session'

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
		@client.expects(:verify_version)
		@client.expects(:cmd_receive_schema)
		@client.expects(:cmd_receive_data)
		@client.expects(:cmd_receive_indexes)
		@client.expects(:cmd_reset_sequences)
		@client.cmd_receive.should.be.nil
	end

	it "checks the version of the server by seeing if it has access" do
		@client.stubs(:server).returns(mock('server'))
		@request = mock('request')
		@client.server.expects(:[]).with('/').returns(@request)
		@request.expects(:get).with({:taps_version => Taps::VERSION})

		lambda { @client.verify_version }.should.not.raise
	end

	it "receives data from a remote taps server" do
		@client.stubs(:puts)
		@progressbar = mock('progressbar')
		ProgressBar.stubs(:new).with('mytable', 2).returns(@progressbar)
		@progressbar.stubs(:inc)
		@progressbar.stubs(:finish)
		@mytable = mock('mytable')
		@client.expects(:fetch_tables_info).returns([ { :mytable => 2 }, 2 ])
		@client.stubs(:db).returns(mock('db'))
		@client.db.stubs(:[]).with(:mytable).returns(@mytable)
		@client.expects(:fetch_table_rows).with(:mytable, 1000, 0).returns([ 1000, { :header => [:x, :y], :data => [[1, 2], [3, 4]] } ])
		@client.expects(:fetch_table_rows).with(:mytable, 1000, 2).returns([ 1000, { }])
		@mytable.expects(:multi_insert).with([:x, :y], [[1, 2], [3, 4]])

		lambda { @client.cmd_receive_data }.should.not.raise
	end

	it "fetches tables info from taps server" do
		@marshal_data = Marshal.dump({ :mytable => 2 })
		@client.session_resource.stubs(:[]).with('tables').returns(mock('tables'))
		@client.session_resource['tables'].stubs(:get).with(:taps_version => Taps::VERSION).returns(@marshal_data)
		@client.fetch_tables_info.should == [ { :mytable => 2 }, 2 ]
	end

	it "fetches table rows given a chunksize and offset from taps server" do
		@data = { :header => [ :x, :y ], :data => [ [1, 2], [3, 4] ] }
		@gzip_data = Taps::Utils.gzip(Marshal.dump(@data))
		Taps::Utils.stubs(:calculate_chunksize).with(1000).yields.returns(1000)

		@response = mock('response')
		@client.session_resource.stubs(:[]).with('tables/mytable/1000?offset=0').returns(mock('table resource'))
		@client.session_resource['tables/mytable/1000?offset=0'].expects(:get).with(:taps_version => Taps::VERSION).returns(@response)
		@response.stubs(:to_s).returns(@gzip_data)
		@response.stubs(:headers).returns({ :taps_checksum => Taps::Utils.checksum(@gzip_data) })
		@client.fetch_table_rows('mytable', 1000, 0).should == [ 1000, { :header => [:x, :y], :data => [[1, 2], [3, 4]] } ]
	end
end

