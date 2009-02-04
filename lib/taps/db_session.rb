class DbSession < Sequel::Model
	set_schema do
		primary_key :id
		text :key
		text :database_url
		timestamp :started_at
		timestamp :last_access
	end

	def connection
		@@connections ||= {}
		@@connections[key] ||= Sequel.connect(database_url)
	end

	def disconnect
		if defined? @@connections and @@connections[key]
			@@connections[key].disconnect
			@@connections.delete key
		end
	end
end

DbSession.db = Sequel.connect(Taps::Config.taps_database_url)

DbSession.create_table unless DbSession.table_exists?
