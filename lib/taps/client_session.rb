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
		uri = server['sessions'].post('', :taps_version => Taps.version)
		server[uri]
	end

	def set_session(uri)
		@session_resource = server[uri]
	end

	def close_session
		@session_resource.delete(:taps_version => Taps.version) if @session_resource
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

	def cmd_send
		verify_server
		cmd_send_schema
		cmd_send_data
		cmd_send_indexes
		cmd_send_reset_sequences
	end

	def cmd_send_indexes
		puts "Sending indexes"

		index_data = `#{File.dirname(__FILE__)}/../../bin/schema indexes #{database_url}`
		session_resource['indexes'].post(index_data, :taps_version => Taps.version)
	end

	def cmd_send_schema
		puts "Sending schema"

		schema_data = `#{File.dirname(__FILE__)}/../../bin/schema dump #{database_url}`
		session_resource['schema'].post(schema_data, :taps_version => Taps.version)
	end

	def cmd_send_reset_sequences
		puts "Resetting sequences"

		session_resource["reset_sequences"].post('', :taps_version => Taps.version)
	end

	def cmd_send_data
		puts "Sending data"

		db.tables.each do |table_name|
			table = db[table_name]
			count = table.count
			columns = table.columns
			order = columns.include?(:id) ? :id : columns.first
			chunksize = self.default_chunksize

			progress = ProgressBar.new(table_name.to_s, count)

			offset = 0
			loop do
				rows = Taps::Utils.format_data(table.order(order).limit(chunksize, offset).all)
				break if rows == { }

				gzip_data = Taps::Utils.gzip(Marshal.dump(rows))

				chunksize = Taps::Utils.calculate_chunksize(chunksize) do
					begin
						session_resource["tables/#{table_name}"].post(gzip_data,
							:taps_version => Taps.version,
							:content_type => 'application/octet-stream',
							:taps_checksum => Taps::Utils.checksum(gzip_data).to_s)
					rescue RestClient::RequestFailed => e
						# retry the same data, it got corrupted somehow.
						if e.http_code == 412
							next
						end
						raise
					end
				end

				progress.inc(rows[:data].size)
				offset += rows[:data].size
			end

			progress.finish
		end
	end

	def cmd_receive
		verify_server
		cmd_receive_schema
		cmd_receive_data
		cmd_receive_indexes
		cmd_reset_sequences
	end

	def cmd_receive_data
		puts "Receiving data"

		tables_with_counts, record_count = fetch_tables_info

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

				table.multi_insert(rows[:header], rows[:data])

				progress.inc(rows[:data].size)
				offset += rows[:data].size
			end

			progress.finish
		end
	end

	class CorruptedData < Exception; end

	def fetch_table_rows(table_name, chunksize, offset)
		response = nil
		chunksize = Taps::Utils.calculate_chunksize(chunksize) do
			response = session_resource["tables/#{table_name}/#{chunksize}?offset=#{offset}"].get(:taps_version => Taps.version)
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

	def fetch_tables_info
		retries = 0
		max_retries = 1
		begin
			tables_with_counts = Marshal.load(session_resource['tables'].get(:taps_version => Taps.version))
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

		schema_data = session_resource['schema'].get(:taps_version => Taps.version)
		output = Taps::Utils.load_schema(database_url, schema_data)
		puts output if output
	end

	def cmd_receive_indexes
		puts "Receiving indexes"

		index_data = session_resource['indexes'].get(:taps_version => Taps.version)

		output = Taps::Utils.load_indexes(database_url, index_data)
		puts output if output
	end

	def cmd_reset_sequences
		puts "Resetting sequences"

		output = `#{File.dirname(__FILE__)}/../../bin/schema reset_db_sequences #{database_url}`
		puts output if output
	end

	def format_number(num)
		num.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
	end

	def verify_server
		begin
			server['/'].get(:taps_version => Taps.version)
		rescue RestClient::RequestFailed => e
			if e.http_code == 417
				puts "#{remote_url} is running a different version of taps."
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
