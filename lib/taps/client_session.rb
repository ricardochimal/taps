require 'rest_client'
require 'sequel'
require 'zlib'

require File.dirname(__FILE__) + '/progress_bar'
require File.dirname(__FILE__) + '/config'
require File.dirname(__FILE__) + '/utils'

module Taps
class ClientSession
	attr_reader :database_url, :remote_url, :default_chunksize

	def initialize(database_url, remote_url, default_chunksize)
		@database_url = database_url
		@remote_url = remote_url
		@default_chunksize = default_chunksize
	end

	def self.start(database_url, remote_url, default_chunksize, &block)
		s = new(database_url, remote_url, default_chunksize)
		yield s
		s.close_session
	end

	def self.quickstart(&block)
		start(Taps::Config.database_url, Taps::Config.remote_url, Taps::Config.chunksize) do |s|
			yield s
		end
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
		uri = server['sessions'].post('', http_headers)
		server[uri]
	end

	def set_session(uri)
		@session_resource = server[uri]
	end

	def close_session
		@session_resource.delete(http_headers) if @session_resource
	end

	def safe_url(url)
		url.sub(/\/\/(.+?)?:(.*?)@/, '//\1:[hidden]@')
	end

	def safe_remote_url
		safe_url(remote_url)
	end

	def safe_database_url
		safe_url(database_url)
	end

	def http_headers(extra = {})
		{ :taps_version => Taps.compatible_version }.merge(extra)
	end

	def cmd_send
		begin
			verify_server
			cmd_send_schema
			cmd_send_data
			cmd_send_indexes
			cmd_send_reset_sequences
		rescue RestClient::Exception => e
			if e.respond_to?(:response)
				puts "!!! Caught Server Exception"
				puts "#{e.response.body}"
				exit(1)
			else
				raise
			end
		end
	end

	def cmd_send_indexes
		puts "Sending indexes"

		index_data = Taps::Utils.schema_bin(:indexes, database_url)
		session_resource['indexes'].post(index_data, http_headers)
	end

	def cmd_send_schema
		puts "Sending schema"

		schema_data = Taps::Utils.schema_bin(:dump, database_url)
		session_resource['schema'].post(schema_data, http_headers)
	end

	def cmd_send_reset_sequences
		puts "Resetting sequences"

		session_resource["reset_sequences"].post('', http_headers)
	end

	def cmd_send_data
		puts "Sending data"

		tables_with_counts, record_count = fetch_tables_info

		puts "#{tables_with_counts.size} tables, #{format_number(record_count)} records"


		db.tables.each do |table_name|
			table = db[table_name]
			count = table.count
			order = Taps::Utils.order_by(db, table_name)
			chunksize = self.default_chunksize
			string_columns = Taps::Utils.incorrect_blobs(db, table_name)

			progress = ProgressBar.new(table_name.to_s, count)

			offset = 0
			loop do
				row_size = 0
				chunksize = Taps::Utils.calculate_chunksize(chunksize) do |c|
					rows = Taps::Utils.format_data(table.order(*order).limit(c, offset).all, string_columns)
					break if rows == { }

					row_size = rows[:data].size
					gzip_data = Taps::Utils.gzip(Marshal.dump(rows))

					begin
						session_resource["tables/#{table_name}"].post(gzip_data, http_headers({
							:content_type => 'application/octet-stream',
							:taps_checksum => Taps::Utils.checksum(gzip_data).to_s}))
					rescue RestClient::RequestFailed => e
						# retry the same data, it got corrupted somehow.
						if e.http_code == 412
							next
						end
						raise
					end
				end

				progress.inc(row_size)
				offset += row_size

				break if row_size == 0
			end

			progress.finish
		end
	end

	def fetch_tables_info
		record_count = 0
		tables = db.tables
		tables_with_counts = tables.inject({}) do |accum, table|
			accum[table] = db[table].count
			record_count += accum[table]
			accum
		end

		[ tables_with_counts, record_count ]
	end

	def cmd_receive
		begin
			verify_server
			cmd_receive_schema
			cmd_receive_data
			cmd_receive_indexes
			cmd_reset_sequences
		rescue RestClient::Exception => e
			if e.respond_to?(:response)
				puts "!!! Caught Server Exception"
				puts "#{e.response.body}"
				exit(1)
			else
				raise
			end
		end
	end

	def cmd_receive_data
		puts "Receiving data"

		tables_with_counts, record_count = fetch_remote_tables_info

		puts "#{tables_with_counts.size} tables, #{format_number(record_count)} records"

		tables_with_counts.each do |table_name, count|
			table = db[table_name.to_sym]
			chunksize = default_chunksize

			progress = ProgressBar.new(table_name.to_s, count)

			offset = 0
			loop do
				begin
					chunksize, rows = fetch_table_rows(table_name, chunksize, offset)
				rescue CorruptedData
					next
				end
				break if rows == { }

				table.import(rows[:header], rows[:data])

				progress.inc(rows[:data].size)
				offset += rows[:data].size
			end

			progress.finish
		end
	end

	class CorruptedData < Exception; end

	def fetch_table_rows(table_name, chunksize, offset)
		response = nil
		chunksize = Taps::Utils.calculate_chunksize(chunksize) do |c|
			response = session_resource["tables/#{table_name}/#{c}?offset=#{offset}"].get(http_headers)
		end
		raise CorruptedData unless Taps::Utils.valid_data?(response.to_s, response.headers[:taps_checksum])

		begin
			rows = Marshal.load(Taps::Utils.gunzip(response.to_s))
		rescue Object => e
			puts "Error encountered loading data, wrote the data chunk to dump.#{Process.pid}.gz"
			File.open("dump.#{Process.pid}.gz", "w") { |f| f.write(response.to_s) }
			raise
		end
		[chunksize, rows]
	end

	def fetch_remote_tables_info
		retries = 0
		max_retries = 1
		begin
			tables_with_counts = Marshal.load(session_resource['tables'].get(http_headers))
			record_count = tables_with_counts.values.inject(0) { |a,c| a += c }
		rescue RestClient::Exception
			retries += 1
			retry if retries <= max_retries
			puts "Unable to fetch tables information from #{remote_url}. Please check the server log."
			exit(1)
		end

		[ tables_with_counts, record_count ]
	end

	def cmd_receive_schema
		puts "Receiving schema"

		schema_data = session_resource['schema'].get(http_headers)
		output = Taps::Utils.load_schema(database_url, schema_data)
		puts output if output
	end

	def cmd_receive_indexes
		puts "Receiving indexes"

		index_data = session_resource['indexes'].get(http_headers)

		output = Taps::Utils.load_indexes(database_url, index_data)
		puts output if output
	end

	def cmd_reset_sequences
		puts "Resetting sequences"

		output = Taps::Utils.schema_bin(:reset_db_sequences, database_url)
		puts output if output
	end

	def format_number(num)
		num.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
	end

	def verify_server
		begin
			server['/'].get(http_headers)
		rescue RestClient::RequestFailed => e
			if e.http_code == 417
				puts "#{safe_remote_url} is running a different minor version of taps."
				puts "#{e.response.body}"
				exit(1)
			else
				raise
			end
		rescue RestClient::Unauthorized
			puts "Bad credentials given for #{safe_remote_url}"
			exit(1)
		rescue Errno::ECONNREFUSED
			puts "Can't connect to #{safe_remote_url}. Please check that it's running"
			exit(1)
		end
	end
end
end
