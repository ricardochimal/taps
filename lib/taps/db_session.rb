require 'thread'

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

	@@connections = {}
	@@mutex = Mutex.new

	def connection
		@@mutex.synchronize {
			conn =
				if @@connections.key?(key)
					@@connections[key].first
				else
					Sequel.connect(database_url)
				end
			@@connections[key] = [conn, Time.now]
			return conn
		}
	end

	def disconnect
		@@mutex.synchronize {
			if @@connections.key?(key)
				conn, time = @@connections.delete(key)
				conn.disconnect
			end
		}
	end

	# Removes connections that have not been accessed within the
	# past thirty seconds.
	def self.cleanup
		@@mutex.synchronize {
			now = Time.now
			@@connections.each do |key, (conn, time)|
				if now - time > 30
					@@connections.delete(key)
					conn.disconnect
				end
			end
		}
	end

	Thread.new {
		while true
			sleep 30
			cleanup
		end
	}.run
end

DbSession.create_table! unless DbSession.table_exists?
