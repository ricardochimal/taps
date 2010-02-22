module Taps

class DataStream
	attr_reader :db, :table_name, :state

	def initialize(db, table_name)
		@db = db
		@table_name = table_name
		@state = { :offset => 0 }
		@complete = false
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
		Taps::Utils.format_data(table.order(*order_by).limit(chunksize, state[:offset]).all, string_columns)
	end

	def compress_rows(rows)
		Taps::Utils.gzip(Marshal.dump(rows))
	end

	def fetch(chunksize)
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

	def self.factory(db, table_name)
		if Taps::Utils.single_integer_primary_key(db, table_name)
			DataStreamKeyed.new(db, table_name)
		else
			DataStream.new(db, table_name)
		end
	end
end


class DataStreamKeyed < DataStream
	attr_accessor :buffer

	def initialize(*args)
		super(*args)
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
