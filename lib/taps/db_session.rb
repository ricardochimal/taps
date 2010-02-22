Sequel::Model.db = Sequel.connect(Taps::Config.taps_database_url)

class DbSession < Sequel::Model
	plugin :schema
	set_schema do
		primary_key :id
		text :key
		text :database_url
		timestamp :started_at
		timestamp :last_access
	end

	def connection
		@connnection ||= Sequel.connect(database_url)
	end

	def disconnect
		connection.disconnect if connection
	end

	def conn
		yield connection if block_given?
	ensure
		disconnect
	end
end

DbSession.create_table! unless DbSession.table_exists?
