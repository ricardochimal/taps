#Sequel::Model.require_valid_table = false
Sequel::Model.strict_param_setting = false
Sequel::Model.db = Sequel.connect(Taps::Config.taps_database_url)

Sequel::Model.db.create_table? :db_sessions do
  primary_key :id
  text :key
  text :database_url
  timestamp :started_at
  timestamp :last_access
end

class DbSession < Sequel::Model
  def conn
    Sequel.connect(database_url) do |db|
      yield db if block_given?
    end
  end
end
