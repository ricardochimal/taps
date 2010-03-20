require 'rest_client'
require 'sequel'
require 'zlib'

require 'taps/progress_bar'
require 'taps/config'
require 'taps/utils'
require 'taps/data_stream'

# disable warnings, rest client makes a lot of noise right now
$VERBOSE = nil

module Taps

class Operation
	attr_reader :database_url, :remote_url, :opts

	def initialize(database_url, remote_url, opts={})
		@database_url = database_url
		@remote_url = remote_url
		@opts = opts
	end

	def default_chunksize
		opts[:default_chunksize]
	end

	def completed_tables
		opts[:completed_tables] ||= []
	end

	def stream_state
		opts[:stream_state] ||= {}
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

class Pull < Operation
	def run
		begin
			verify_server
			pull_schema
			pull_data
			pull_indexes
			pull_reset_sequences
		rescue RestClient::Exception => e
			if e.respond_to?(:response)
				puts "!!! Caught Server Exception"
				puts "HTTP CODE: #{e.http_code}"
				puts "#{e.response}"
				exit(1)
			else
				raise
			end
		end
	end

	def pull_schema
		puts "Receiving schema"

		schema_data = session_resource['pull/schema'].get(http_headers).body.to_s
		output = Taps::Utils.load_schema(database_url, schema_data)
		puts output if output
	end

	def pull_data
		puts "Receiving data (new)"

		puts "#{tables.size} tables, #{format_number(record_count)} records"

		tables.each do |table_name, count|
			progress = ProgressBar.new(table_name.to_s, count)
			stream = Taps::DataStream.factory(db, {
				:chunksize => default_chunksize,
				:table_name => table_name
			})
			pull_data_from_table(stream, progress)
		end
	end

	def pull_data_from_table(stream, progress)
		loop do
			begin
				size = stream.fetch_remote(session_resource['pull/table'], http_headers)
				break if stream.complete?
				progress.inc(size)
				stream.error = false
				stream_state = stream.to_json
			rescue DataStream::CorruptedData => e
				puts "Corrupted Data Received #{e.message}, retrying..."
				stream.error = true
				next
			end
		end

		progress.finish

		stream_state = {}
		completed_tables << stream.table_name.to_sym
	end

	def tables
		@tables ||= begin
			h = {}
			remote_tables_info.each do |table_name, count|
				next if completed_tables.include?(table_name.to_s)
				h[table_name.to_s] = count

			end
			h
		end
	end

	def record_count
		@record_count ||= remote_tables_info.values.inject(0) { |a,c| a += c }
	end

	def remote_tables_info
		opts[:remote_tables_info] ||= fetch_remote_tables_info
	end

	def fetch_remote_tables_info
		retries = 0
		max_retries = 1
		begin
			tables_with_counts = Marshal.load(session_resource['pull/tables'].get(http_headers).body.to_s)
		rescue RestClient::Exception
			retries += 1
			retry if retries <= max_retries
			puts "Unable to fetch tables information from #{remote_url}. Please check the server log."
			exit(1)
		end

		tables_with_counts
	end

	def pull_schema
		puts "Receiving schema"

		schema_data = session_resource['pull/schema'].get(http_headers).body.to_s
		output = Taps::Utils.load_schema(database_url, schema_data)
		puts output if output
	end

	def pull_indexes
		puts "Receiving indexes"

		index_data = session_resource['pull/indexes'].get(http_headers).body.to_s

		output = Taps::Utils.load_indexes(database_url, index_data)
		puts output if output
	end

	def pull_reset_sequences
		puts "Resetting sequences"

		output = Taps::Utils.schema_bin(:reset_db_sequences, database_url)
		puts output if output
	end
end

end
