require 'sequel'
require 'sqlite3'
require 'yaml'

module Taps
	def self.version_yml
		@@version_yml ||= YAML.load(File.read(File.dirname(__FILE__) + '/../../VERSION.yml'))
	end

	def self.version
		version = "#{version_yml[:major]}.#{version_yml[:minor]}.#{version_yml[:patch]}"
		version += ".#{version_yml[:build]}" if version_yml[:build]
		version
	end

	def self.compatible_version
		"#{version_yml[:major]}.#{version_yml[:minor]}"
	end

	def self.exiting=(val)
		@@exiting = val
	end

	def exiting?
		(@@exiting ||= false) == true
	end

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
