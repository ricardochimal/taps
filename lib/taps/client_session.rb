require 'rest_client'
require 'sequel'
require 'json'

module Taps
class ClientSession
	attr_reader :database_url, :remote_url

	def initialize(database_url, remote_url)
		@database_url = database_url
		@remote_url = remote_url
	end

	def self.start(database_url, remote_url, &block)
		s = new(database_url, remote_url)
		yield s
		s.close_session
	end

	def db
		@db ||= Sequel.connect(database_url)
	end

	def server
		@server ||= RestClient::Resource.new(remote_url)
	end

	def session_resource
		@session_resource ||= open_session
	end

	def open_session
		uri = server['sessions'].post ''
		server[uri]
	end

	def close_session
		@session_resource.delete if @session_resource
	end

	def cmd_send
		puts "Sending schema and data from local database #{@database_url} to remote taps server at #{@remote_url}"

		chunk_size = 500

		db.tables.each do |table_name|
			table = db[table_name]
			count = table.count
			puts "#{table_name} - #{count} records"

			page = 1
			while (page-1)*chunk_size < count
				data = table.order(:id).paginate(page, chunk_size).all.to_json
				session_resource[table_name].post data
				print "."
				page += 1
			end

			puts "done."
		end
	end

	def cmd_receive
		cmd_receive_schema
		cmd_receive_data
	end

	def cmd_receive_data
		puts "Receiving data from remote taps server #{@remote_url} into local database #{@database_url}"

		db.tables.each do |table_name|
			table = db[table_name]
			print "#{table_name}"

			page = 1
			loop do
				rows = JSON.parse session_resource["#{table_name}?page=#{page}"].get
				break if rows.size == 0

				db.transaction do
					rows.each { |row| table << row }
				end
				print "."

				page += 1
			end

			puts "done."
		end
	end

	def cmd_receive_schema
		puts "Receiving schema from remote taps server #{@remote_url} into local database #{@database_url}"

		schema = JSON.parse session_resource['schema'].get

		schema.each do |table, fields|
			puts "Creating table #{table} with #{fields.size} fields"
			db.create_table(table) do
				fields.each do |name, opts|
					column name, opts['db_type']
				end
			end
		end
	end
end
end
