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

  def conn
    Sequel.connect(database_url) do |db|
      yield db if block_given?
    end
  end
end

DbSession.create_table! unless DbSession.table_exists?
