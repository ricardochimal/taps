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
end

end
