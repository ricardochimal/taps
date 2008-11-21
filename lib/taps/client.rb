require 'rest_client'
require 'sequel'
require 'json'

module Taps
class Client
	def initialize(database_url, remote_url)
		@database_url = database_url
		@remote_url = remote_url
	end

	def send
		puts "Sending schema and data from local database #{@database_url} to remote taps server at #{@remote_url}"

		db = Sequel.connect(@database_url)
		server = RestClient::Resource.new(@remote_url)

		uri = server['sessions'].post ''
		session = server[uri]

		chunk_size = 100

		db.tables.each do |table_name|
			table = db[table_name]
			count = table.count
			puts "#{table_name} - #{count} records"

			page = 1
			while (page-1)*chunk_size < count
				data = table.order(:id).paginate(page, chunk_size).all.to_json
				session[table_name].post data
				print "."
				page += 1
			end

			puts "done."
		end

		session.delete
	end

	def receive
		puts "Receiving schema and data from remote taps server #{@remote_url} into local database #{@database_url}"

		db = Sequel.connect(@database_url)
		server = RestClient::Resource.new(@remote_url)

		uri = server['sessions'].post ''
		session = server[uri]

		db.tables.each do |table_name|
			table = db[table_name]
			print "#{table_name}"

			page = 1
			loop do
				rows = JSON.parse session["#{table_name}?page=#{page}"].get
				break if rows.size == 0

				db.transaction do
					rows.each { |row| table << row }
				end
				print "."

				page += 1
			end

			puts "done."
		end

		session.delete
	end

	def receive_schema
		puts "Receiving just schema from remote taps server #{@remote_url} into local database #{@database_url}"

		db = Sequel.connect(@database_url)
		server = RestClient::Resource.new(@remote_url)

		uri = server['sessions'].post ''
		session = server[uri]

		schema = JSON.parse session['schema'].get

		schema.each do |table, fields|
			puts "Creating table #{table} with #{fields.size} fields"
			db.create_table(table) do
				fields.each do |name, opts|
					column name, opts['db_type']
				end
			end
		end

		session.delete
	end
end
end
