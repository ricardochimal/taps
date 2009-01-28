require 'rubygems'
gem 'activerecord', '>= 2.2.2'
gem 'activesupport', '>= 2.2.2'
require 'active_record'
require 'active_support'
require 'stringio'
require 'uri'

module Taps
module Schema
	extend self

	def create_config(url)
		uri = URI.parse(url)
		config = {
			'adapter' => (uri.scheme == 'postgres') ? 'postgresql' : uri.scheme,
			'database' => uri.path.blank? ? uri.host : uri.path.split('/')[1],
			'username' => uri.user,
			'password' => uri.password,
			'host' => uri.host,
		}
	end

	def connection(database_url)
		config = create_config(database_url)
		ActiveRecord::Base.establish_connection(config)
	end

	def dump(database_url)
		connection(database_url)

		stream = StringIO.new
		ActiveRecord::SchemaDumper.ignore_tables = []
		ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, stream)
		stream.string
	end

	def load(database_url, schema)
		connection(database_url)
		eval(schema)
		ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
	end
end
end
