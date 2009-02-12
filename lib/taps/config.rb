require 'sequel'

module Taps

VERSION = '0.2.2'

class Config
	class << self
		attr_accessor :taps_database_url
		attr_accessor :login, :password, :database_url, :remote_url
		attr_accessor :chunksize

		def verify_database_url
			db = Sequel.connect(self.database_url)
			db.tables
			db.disconnect
		rescue Object => e
			puts "Failed to connect to database:\n  #{e.class} -> #{e}"
			exit 1
		end
	end
end
end
