require File.dirname(__FILE__) + '/base'
require File.dirname(__FILE__) + '/../lib/taps/schema'

describe Taps::Schema do
	before do
		Taps::AdapterHacks.stubs(:load)
		@connection = mock("AR connection")
		ActiveRecord::Base.stubs(:connection).returns(@connection)
	end

	it "parses a database url and returns a config hash for activerecord" do
		Taps::Schema.create_config("postgres://myuser:mypass@localhost/mydb").should == {
			'adapter' => 'postgresql',
			'database' => 'mydb',
			'username' => 'myuser',
			'password' => 'mypass',
			'host' => 'localhost'
		}
	end

	it "translates sqlite in the database url to sqlite3" do
		Taps::Schema.create_config("sqlite://mydb")['adapter'].should == 'sqlite3'
	end

	it "translates sqlite database path" do
		Taps::Schema.create_config("sqlite://pathtodb/mydb")['database'].should == 'pathtodb/mydb'
		Taps::Schema.create_config("sqlite:///pathtodb/mydb")['database'].should == '/pathtodb/mydb'
	end

	it "connects activerecord to the database" do
		Taps::Schema.expects(:create_config).with("postgres://myuser:mypass@localhost/mydb").returns("db config")
		ActiveRecord::Base.expects(:establish_connection).with("db config").returns(true)
		Taps::Schema.connection("postgres://myuser:mypass@localhost/mydb").should == true
	end

	it "resets the db tables' primary keys" do
		Taps::Schema.stubs(:connection)
		ActiveRecord::Base.connection.expects(:respond_to?).with(:reset_pk_sequence!).returns(true)
		ActiveRecord::Base.connection.stubs(:tables).returns(['table1'])
		ActiveRecord::Base.connection.expects(:reset_pk_sequence!).with('table1')
		should.not.raise { Taps::Schema.reset_db_sequences("postgres://myuser:mypass@localhost/mydb") }
	end
end

