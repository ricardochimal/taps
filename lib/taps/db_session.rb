DB = Sequel.connect(Taps::Config.taps_database_url)

#DbSession.create_table! unless DbSession.table_exists?
DB.create_table? :db_session do
  primary_key :id
  text :key
  text :database_url
  timestamp :started_at
  timestamp :last_access
end

Sequel::Model.db = DB
Sequel::Model.require_valid_table = false

class DbSession < Sequel::Model
  def conn
    Sequel.connect(database_url) do |db|
      yield db if block_given?
    end
  end
end
