require 'active_record'
require 'active_support'
require 'stringio'
require 'uri'

require File.dirname(__FILE__) + '/adapter_hacks'

module Taps
module Schema
	extend self

	def create_config(url)
		uri = URI.parse(url)
		adapter = uri.scheme
		adapter = 'postgresql' if adapter == 'postgres'
		adapter = 'sqlite3' if adapter == 'sqlite'
		config = {
			'adapter' => adapter,
			'database' => uri.path.blank? ? uri.host : uri.path.split('/')[1],
			'username' => uri.user,
			'password' => uri.password,
			'host' => uri.host,
		}
		config = sqlite_config(url) if config['adapter'] == 'sqlite3'
		config
	end

	def sqlite_config(url)
		m = %r{(sqlite3?)://(.+)}.match(url)
		database = m[2]
		database, q = database.split('?')
		{ 'adapter' => 'sqlite3', 'database' => database }
	end

	def connection(database_url)
		config = create_config(database_url)
		Taps::AdapterHacks.load(config['adapter'])
		ActiveRecord::Base.establish_connection(config)
	end

	def dump(database_url)
		connection(database_url)

		stream = StringIO.new
		ActiveRecord::SchemaDumper.ignore_tables = []
		ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, stream)
		stream.string
	end

	def dump_without_indexes(database_url)
		schema = dump(database_url)
		schema.split("\n").collect do |line|
			if line =~ /^\s+add_index/
				line = "##{line}"
			end
			line
		end.join("\n")
	end

	def indexes(database_url)
		schema = dump(database_url)
		schema.split("\n").collect do |line|
			line if line =~ /^\s+add_index/
		end.uniq.join("\n")
	end

	def load(database_url, schema)
		connection(database_url)
		eval(schema)
	end

	def load_indexes(database_url, indexes)
		connection(database_url)

		schema =<<EORUBY
ActiveRecord::Schema.define do
	#{indexes}
end
EORUBY
		eval(schema)
	end

	def reset_db_sequences(database_url)
		connection(database_url)

		if ActiveRecord::Base.connection.respond_to?(:reset_pk_sequence!)
			ActiveRecord::Base.connection.tables.each do |table|
				ActiveRecord::Base.connection.reset_pk_sequence!(table)
			end
		end
	end
end
end
