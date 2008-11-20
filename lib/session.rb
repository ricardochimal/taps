class Session < Sequel::Model
	set_schema do
		primary_key :id
		text :key
		text :database_url
		timestamp :started_at
		timestamp :last_access
	end
end

Session.create_table unless Session.table_exists?
