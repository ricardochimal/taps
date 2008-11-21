class DbSession < Sequel::Model
	set_schema do
		primary_key :id
		text :key
		text :database_url
		timestamp :started_at
		timestamp :last_access
	end

	def connection
		Thread.current[:connections] ||= {}
		Thread.current[:connections][key] ||= Sequel.connect(database_url)
	end

	def disconnect
		if Thread.current[:connections] and Thread.current[:connections][key]
			Thread.current[:connections][key].disconnect
			Thread.current[:connections].delete key
		end
	end
end

DbSession.create_table unless DbSession.table_exists?
