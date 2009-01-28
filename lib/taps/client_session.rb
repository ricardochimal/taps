require 'rest_client'
require 'sequel'
require 'json'

require File.dirname(__FILE__) + '/progress_bar'

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

		db.tables.each do |table_name|
			table = db[table_name]
			count = table.count
			puts "#{table_name} - #{count} records"

			page = 1
			while (page-1)*ChunkSize < count
				data = table.order(:id).paginate(page, ChunkSize).all.to_json
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
		cmd_receive_indexes
	end

	def cmd_receive_data
		puts "Receiving data from remote taps server #{@remote_url} into local database #{@database_url}"

		tables_with_counts = JSON.parse session_resource['tables'].get
		record_count = tables_with_counts.values.inject(0) { |a,c| a += c }

		puts "#{tables_with_counts.size} tables, #{format_number(record_count)} records"

		tables_with_counts.each do |table_name, count|
			table = db[table_name.to_sym]
			pages = (count / ChunkSize).round

			progress = ProgressBar.new(table_name, pages)

			page = 1
			loop do
				rows = JSON.parse session_resource["#{table_name}?page=#{page}"].get
				break if rows.size == 0

				db.transaction do
					rows.each { |row| table << row }
				end

				progress.inc
				page += 1
			end

			progress.finish
		end
	end

	def cmd_receive_schema
		puts "Receiving schema from remote taps server #{@remote_url} into local database #{@database_url}"

		require 'tempfile'
		schema_data = session_resource['schema'].get

		Tempfile.open('taps') do |tmp|
			File.open(tmp.path, 'w') { |f| f.write(schema_data) }
			puts `#{File.dirname(__FILE__)}/../../bin/schema load #{@database_url} #{tmp.path}`
		end
	end

	def cmd_receive_indexes
		puts "Receiving schema indexes from remote taps server #{@remote_url} into local database #{@database_url}"

		require 'tempfile'
		index_data = session_resource['indexes'].get

		Tempfile.open('taps') do |tmp|
			File.open(tmp.path, 'w') { |f| f.write(index_data) }
			puts `#{File.dirname(__FILE__)}/../../bin/schema load_indexes #{@database_url} #{tmp.path}`
		end
	end

	def format_number(num)
		num.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
	end
end
end
