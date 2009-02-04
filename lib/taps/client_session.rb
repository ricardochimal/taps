require 'rest_client'
require 'sequel'
require 'json'
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
		uri = server['sessions'].post('', :taps_version => Taps::VERSION)
		server[uri]
	end

	def close_session
		@session_resource.delete(:taps_version => Taps::VERSION) if @session_resource
	end

	def cmd_send
		puts "Sending schema and data from local database #{database_url} to remote taps server at #{remote_url}"

		db.tables.each do |table_name|
			table = db[table_name]
			count = table.count
			puts "#{table_name} - #{count} records"

			page = 1
			while (page-1)*ChunkSize < count
				data = table.order(:id).paginate(page, ChunkSize).all.to_json
				session_resource[table_name].post(data, :taps_version => Taps::VERSION)
				print "."
				page += 1
			end

			puts "done."
		end
	end

	def cmd_receive
		verify_version
		cmd_receive_schema
		cmd_receive_data
		cmd_receive_indexes
		cmd_reset_db_sequences
	end

	def cmd_receive_data
		puts "Receiving data from remote taps server #{remote_url} into local database #{database_url}"

		tables_with_counts = Marshal.load(session_resource['tables'].get(:taps_version => Taps::VERSION))
		record_count = tables_with_counts.values.inject(0) { |a,c| a += c }

		puts "#{tables_with_counts.size} tables, #{format_number(record_count)} records"

		tables_with_counts.each do |table_name, count|
			table = db[table_name.to_sym]
			chunksize = default_chunksize

			progress = ProgressBar.new(table_name.to_s, count)

			offset = 0
			loop do
				response = nil
				chunksize = Taps::Utils.calculate_chunksize(chunksize) do
					response = session_resource["#{table_name}/#{chunksize}?offset=#{offset}"].get(:taps_version => Taps::VERSION)
				end
				# retry the same page if the data was corrupted
				next unless Taps::Utils.valid_data?(response.to_s, response.headers[:taps_checksum])
				rows = Marshal.load(Taps::Utils.gunzip(response.to_s))
				break if rows == { }

				table.multi_insert(rows[:header], rows[:data])

				progress.inc(rows[:data].size)
				offset += rows[:data].size
			end

			progress.finish
		end
	end

	def cmd_receive_schema
		puts "Receiving schema from remote taps server #{remote_url} into local database #{database_url}"

		require 'tempfile'
		schema_data = session_resource['schema'].get(:taps_version => Taps::VERSION)

		Tempfile.open('taps') do |tmp|
			File.open(tmp.path, 'w') { |f| f.write(schema_data) }
			puts `#{File.dirname(__FILE__)}/../../bin/schema load #{database_url} #{tmp.path}`
		end
	end

	def cmd_receive_indexes
		puts "Receiving schema indexes from remote taps server #{remote_url} into local database #{database_url}"

		require 'tempfile'
		index_data = session_resource['indexes'].get(:taps_version => Taps::VERSION)

		Tempfile.open('taps') do |tmp|
			File.open(tmp.path, 'w') { |f| f.write(index_data) }
			puts `#{File.dirname(__FILE__)}/../../bin/schema load_indexes #{database_url} #{tmp.path}`
		end
	end

	def cmd_reset_db_sequences
		puts "Resetting db sequences in #{database_url}"

		puts `#{File.dirname(__FILE__)}/../../bin/schema reset_db_sequences #{database_url}`
	end

	def format_number(num)
		num.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
	end

	def verify_version
		server['/'].get(:taps_version => Taps::VERSION)
	rescue RestClient::RequestFailed => e
		if e.http_code == 417
			puts "#{remote_url} is running a different version of taps."
			puts "#{e.response.body}"
			exit(1)
		else
			raise
		end
	end
end
end
