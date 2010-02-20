require 'sequel'
require 'sequel/extensions/schema_dumper'
require 'sequel/extensions/migration'

module Taps
module Schema
	extend self

	def dump(database_url)
		db = Sequel.connect(database_url)
		db.dump_schema_migration(:indexes => false)
	end

	def indexes(database_url)
		db = Sequel.connect(database_url)
		db.dump_indexes_migration
	end

	def load(database_url, schema)
		db = Sequel.connect(database_url)
		eval(schema).apply(db, :up)
	end

	def load_indexes(database_url, indexes)
		db = Sequel.connect(database_url)
		eval(indexes).apply(db, :up)
	end

	def reset_db_sequences(database_url)
		db = Sequel.connect(database_url)
		return unless db.respond_to?(:reset_primary_key_sequence)
		db.tables.each do |table|
			db.reset_primary_key_sequence(table)
		end
	end
end
end
