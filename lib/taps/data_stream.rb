require 'taps/monkey'
require 'taps/multipart'
require 'json'

module Taps

class DataStream
	class CorruptedData < Exception; end

	attr_reader :db, :state

	def initialize(db, state)
		@db = db
		@state = { :offset => 0 }.merge(state)
		@complete = false
	end

	def table_name
		state[:table_name].to_sym
	end

	def to_hash
		state.merge(:klass => self.class.to_s)
	end

	def to_json
		to_hash.to_json
	end

	def string_columns
		@string_columns ||= Taps::Utils.incorrect_blobs(db, table_name)
	end

	def table
		@table ||= db[table_name]
	end

	def order_by
		@order_by ||= Taps::Utils.order_by(db, table_name)
	end

	def increment(row_count)
		state[:offset] += row_count
	end

	def fetch_rows(chunksize)
		ds = table.order(*order_by).limit(chunksize, state[:offset])
		Taps::Utils.format_data(ds.all, string_columns)
	end

	def compress_rows(rows)
		Taps::Utils.gzip(Marshal.dump(rows))
	end

	def fetch(chunksize=nil)
		chunksize ||= state[:chunksize]

		t1 = Time.now
		rows = fetch_rows(chunksize)
		gzip_data = compress_rows(rows)
		t2 = Time.now
		elapsed_time = t2 - t1

		@complete = rows == { }

		[gzip_data, (@complete ? 0 : rows[:data].size), elapsed_time]
	end

	def complete?
		@complete
	end

	def fetch_remote(resource, headers)
		params = fetch_from_resource(resource, headers)
		gzip_data = params[:gzip_data]
		json = params[:json]

		rows = parse_gzip_data(gzip_data, json[:checksum])
		@complete = rows == { }

		unless @complete
			import_rows(rows)
			rows[:data].size
		else
			0
		end
	end

	# this one is used inside the server process
	def fetch_remote_in_server(params)
		json = self.class.parse_json(params[:json])
		gzip_data = params[:gzip_data]

		rows = parse_gzip_data(gzip_data, json[:checksum])
		@complete = rows == { }

		unless @complete
			import_rows(rows)
			rows[:data].size
		else
			0
		end
	end

	def fetch_from_resource(resource, headers)
		res = nil
		state[:chunksize] = Taps::Utils.calculate_chunksize(state[:chunksize]) do |c|
			state[:chunksize] = c
			res = resource.post({:state => self.to_json}, headers)
		end

		begin
			params = Taps::Multipart.parse(res)
			params[:json] = self.class.parse_json(params[:json]) if params.has_key?(:json)
			return params
		rescue JSON::Parser
			raise DataStream::CorruptedData
		end
	end

	def self.parse_json(json)
		hash = JSON.parse(json).symbolize_keys
		hash[:state].symbolize_keys! if hash.has_key?(:state)
		hash
	end

	def parse_gzip_data(gzip_data, checksum)
		raise DataStream::CorruptedData unless Taps::Utils.valid_data?(gzip_data, checksum)

		begin
			return Marshal.load(Taps::Utils.gunzip(gzip_data))
		rescue Object => e
			puts "Error encountered loading data, wrote the data chunk to dump.#{Process.pid}.gz"
			File.open("dump.#{Process.pid}.gz", "w") { |f| f.write(gzip_data) }
			raise
		end
	end

	def import_rows(rows)
		table.import(rows[:header], rows[:data])
		state[:offset] += rows[:data].size
	end

	def self.factory(db, state)
		return DataStream.new(db, state)
		if Taps::Utils.single_integer_primary_key(db, state[:table_name].to_sym)
			DataStreamKeyed.new(db, state)
		else
			DataStream.new(db, state)
		end
	end
end


class DataStreamKeyed < DataStream
	attr_accessor :buffer

	def initialize(db, state)
		super(db, state)
		@state = { :primary_key => order_by.first, :filter => 0 }.merge(state)
		@buffer = []
		setup_state
	end

	def setup_state
		state[:primary_key] = order_by.first
		state[:filter] = 0
	end

	# load the buffer for chunksize * 2
	def load_buffer(chunksize)
		num = 0
		loop do
			data = table.order(*order_by).filter(state[:primary_key] > state[:filter]).limit(chunksize*2).all
			self.buffer += data
			num += data.size
			if data.size > 0
				# keep a record of the last primary key value in the buffer
				state[:filter] = self.buffer.last[ state[:primary_key] ]
			end

			break if num >= chunksize or data.size == 0
		end
	end

	def fetch_rows(chunksize)
		load_buffer(chunksize) if self.buffer.size < chunksize
		Taps::Utils.format_data(buffer.slice(0, chunksize) || [], string_columns)
	end

	def increment(row_count)
		# pop the rows we just successfully sent off the buffer
		@buffer.slice!(0, row_count)
		super
	end
end

end
