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
	attr_reader :session_uri

	def initialize(database_url, remote_url, opts={})
		@database_url = database_url
		@remote_url = remote_url
		@opts = opts
		@exiting = false
		@session_uri = opts[:session_uri]
	end

	def file_prefix
		"op"
	end

	def store_session
		file = "#{file_prefix}_#{Time.now.strftime("%Y%m%d%H%M")}.dat"
		puts "Saving session to #{file}.."
		File.open(file, 'w') do |f|
			f.write(to_hash.to_json)
		end
	end

	def to_hash
		{
			:klass => self.class.to_s,
			:database_url => database_url,
			:session_uri => session_uri,
			:stream_state => stream_state,
			:completed_tables => completed_tables,
		}
	end

	def exiting?
		!!@exiting
	end

	def setup_signal_trap
		trap("INT") {
			puts "\nCompleting current action..."
			@exiting = true
		}

		trap("TERM") {
			puts "\nCompleting current action..."
			@exiting = true
		}
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

	def stream_state=(val)
		opts[:stream_state] = val
	end

	def db
		@db ||= Sequel.connect(database_url)
	end

	def server
		@server ||= RestClient::Resource.new(remote_url)
	end

	def session_resource
		@session_resource ||= begin
			@session_uri ||= server['sessions'].post('', http_headers).to_s
			server[@session_uri]
		end
	end

	def set_session(uri)
		session_uri = uri
		@session_resource = server[session_uri]
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

	def self.factory(type, database_url, remote_url, opts)
		klass = case type
			when :pull then Taps::Pull
			when :push then Taps::Push
			else raise "Unknown Operation Type -> #{type}"
		end

		klass.new(database_url, remote_url, opts)
	end

	def self.resume(remote_url, session)
		klass = session[:klass]
		eval(klass).new(session[:database_url], remote_url, session).resume
	end
end

class Pull < Operation
	def resume
		begin
			verify_server

			setup_signal_trap

			pull_partial_data

			pull_data
			pull_indexes
			pull_reset_sequences
			close_session
		rescue RestClient::Exception => e
			if e.respond_to?(:response)
				puts "!!! Caught Server Exception"
				puts "HTTP CODE: #{e.http_code}"
				puts "#{e.response}"
				puts "#{e.backtrace}"
				exit(1)
			else
				raise
			end
		end
	end

	def file_prefix
		"pull"
	end

	def to_hash
		super.merge(:remote_tables_info => remote_tables_info)
	end

	def run
		begin
			verify_server
			pull_schema

			setup_signal_trap

			pull_data
			pull_indexes
			pull_reset_sequences
			close_session
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

	def pull_partial_data
		table_name = stream_state[:table_name]
		record_count = tables[table_name.to_s]
		puts "Resuming #{table_name}, #{format_number(record_count)} records"

		progress = ProgressBar.new(table_name.to_s, record_count)
		stream = Taps::DataStream.factory(db, stream_state)
		pull_data_from_table(stream, progress)
	end

	def pull_data_from_table(stream, progress)
		loop do
			begin
				if exiting?
					store_session
					exit 0
				end

				size = stream.fetch_remote(session_resource['pull/table'], http_headers)
				break if stream.complete?
				progress.inc(size) unless exiting?
				stream.error = false
				self.stream_state = stream.to_hash
			rescue DataStream::CorruptedData => e
				puts "Corrupted Data Received #{e.message}, retrying..."
				stream.error = true
				next
			end
		end

		progress.finish
		completed_tables << stream.table_name.to_s
		self.stream_state = {}
	end

	def tables
		h = {}
		remote_tables_info.each do |table_name, count|
			next if completed_tables.include?(table_name.to_s)
			h[table_name.to_s] = count
		end
		h
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

class Push < Operation
	def resume
		begin
			verify_server

			setup_signal_trap

			push_partial_data

			push_data
			push_indexes
			push_reset_sequences

		rescue RestClient::Exception => e
			if e.respond_to?(:response)
				puts "!!! Caught Server Exception"
				puts "HTTP CODE: #{e.http_code}"
				puts "#{e.response.body}"
				exit(1)
			else
				raise
			end
		end

	end

	def file_prefix
		"push"
	end

	def to_hash
		super.merge(:local_tables_info => local_tables_info)
	end

	def run
		begin
			verify_server
			setup_signal_trap
			push_schema
			push_data
			push_indexes
			push_reset_sequences
			close_session
		rescue RestClient::Exception => e
			if e.respond_to?(:response)
				puts "!!! Caught Server Exception"
				puts "HTTP CODE: #{e.http_code}"
				puts "#{e.response.body}"
				exit(1)
			else
				raise
			end
		end
	end

	def push_indexes
		puts "Sending indexes"

		index_data = Taps::Utils.schema_bin(:indexes, database_url)
		session_resource['push/indexes'].post(index_data, http_headers)
	end

	def push_schema
		puts "Sending schema"

		schema_data = Taps::Utils.schema_bin(:dump, database_url)
		session_resource['push/schema'].post(schema_data, http_headers)
	end

	def push_reset_sequences
		puts "Resetting sequences"

		session_resource['push/reset_sequences'].post('', http_headers)
	end

	def push_partial_data
		table_name = stream_state[:table_name]
		record_count = tables[table_name.to_s]
		puts "Resuming #{table_name}, #{format_number(record_count)} records"
		progress = ProgressBar.new(table_name.to_s, record_count)
		stream = Taps::DataStream.factory(db, stream_state)
		push_data_from_table(stream, progress)
	end

	def push_data
		puts "Sending data"

		puts "#{tables.size} tables, #{format_number(record_count)} records"

		tables.each do |table_name, count|
			stream = Taps::DataStream.factory(db,
				:table_name => table_name,
				:chunksize => default_chunksize)
			progress = ProgressBar.new(table_name.to_s, count)
			push_data_from_table(stream, progress)
		end
	end

	def push_data_from_table(stream, progress)
		loop do
			if exiting?
				store_session
				exit 0
			end

			row_size = 0
			chunksize = stream.state[:chunksize]
			chunksize = Taps::Utils.calculate_chunksize(chunksize) do |c|
				stream.state[:chunksize] = c
				gzip_data, row_size, elapsed_time = stream.fetch
				break if stream.complete?

				data = {
					:state => stream.to_hash,
					:checksum => Taps::Utils.checksum(gzip_data).to_s
				}

				begin
					content, content_type = Taps::Multipart.create do |r|
						r.attach :name => :gzip_data,
							:payload => gzip_data,
							:content_type => 'application/octet-stream'
						r.attach :name => :json,
							:payload => data.to_json,
							:content_type => 'application/json'
					end
					session_resource['push/table'].post(content, http_headers(:content_type => content_type))
					self.stream_state = stream.to_hash
				rescue RestClient::RequestFailed => e
					# retry the same data, it got corrupted somehow.
					if e.http_code == 412
						next
					end
					raise
				end
				elapsed_time
			end

			progress.inc(row_size)

			stream.increment(row_size)
			break if stream.complete?
		end

		progress.finish
		completed_tables << stream.table_name.to_s
		self.stream_state = {}
	end

	def local_tables_info
		opts[:local_tables_info] ||= fetch_local_tables_info
	end

	def tables
		h = {}
		local_tables_info.each do |table_name, count|
			next if completed_tables.include?(table_name.to_s)
			h[table_name.to_s] = count
		end
		h
	end

	def record_count
		@record_count ||= local_tables_info.values.inject(0) { |a,c| a += c }
	end

	def fetch_local_tables_info
		tables_with_counts = {}
		db.tables.each do |table|
			tables_with_counts[table] = db[table].count
		end
		tables_with_counts
	end

end

end
