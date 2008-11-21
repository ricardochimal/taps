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

			puts
		end

		session.delete
	end
end
end
