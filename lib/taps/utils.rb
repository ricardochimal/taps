require 'zlib'
require 'stringio'
require 'time'
require 'tempfile'

module Taps
module Utils
	extend self

	def windows?
		return @windows if defined?(@windows)
		require 'rbconfig'
		@windows = !!(::Config::CONFIG['host_os'] =~ /mswin|mingw/)
	end

	def bin(cmd)
		cmd = "#{cmd}.cmd" if windows?
		cmd
	end

	def checksum(data)
		Zlib.crc32(data)
	end

	def valid_data?(data, crc32)
		Zlib.crc32(data) == crc32.to_i
	end

	def base64encode(data)
		[data].pack("m")
	end

	def base64decode(data)
		data.unpack("m").first
	end

	def format_data(data, opts={})
		return {} if data.size == 0
		string_columns = opts[:string_columns] || []

		header = data[0].keys
		only_data = data.collect do |row|
			row = blobs_to_string(row, string_columns)
			header.collect { |h| row[h] }
		end
		{ :header => header, :data => only_data }
	end

	# mysql text and blobs fields are handled the same way internally
	# this is not true for other databases so we must check if the field is
	# actually text and manually convert it back to a string
	def incorrect_blobs(db, table)
		return [] if (db.url =~ /mysql:\/\//).nil?

		columns = []
		db.schema(table).each do |data|
			column, cdata = data
			columns << column if cdata[:db_type] =~ /text/
		end
		columns
	end

	def blobs_to_string(row, columns)
		return row if columns.size == 0
		columns.each do |c|
			row[c] = row[c].to_s if row[c].kind_of?(Sequel::SQL::Blob)
		end
		row
	end

	def calculate_chunksize(old_chunksize)
		chunksize = old_chunksize

		retries = 0
		time_in_db = 0
		begin
			t1 = Time.now
			time_in_db = yield chunksize
			time_in_db = time_in_db.to_f rescue 0
		rescue Errno::EPIPE, RestClient::RequestFailed, RestClient::RequestTimeout
			retries += 1
			raise if retries > 2

			# we got disconnected, the chunksize could be too large
			# on first retry change to 10, on successive retries go down to 1
			chunksize = (retries == 1) ? 10 : 1

			retry
		end

		t2 = Time.now

		diff = t2 - t1 - time_in_db

		new_chunksize = if retries > 0
			chunksize
		elsif diff > 3.0
			(chunksize / 3).ceil
		elsif diff > 1.1
			chunksize - 100
		elsif diff < 0.8
			chunksize * 2
		else
			chunksize + 100
		end
		new_chunksize = 1 if new_chunksize < 1
		new_chunksize
	end

	def load_schema(database_url, schema_data)
		Tempfile.open('taps') do |tmp|
			File.open(tmp.path, 'w') { |f| f.write(schema_data) }
			schema_bin(:load, database_url, tmp.path)
		end
	end

	def load_indexes(database_url, index_data)
		Tempfile.open('taps') do |tmp|
			File.open(tmp.path, 'w') { |f| f.write(index_data) }
			schema_bin(:load_indexes, database_url, tmp.path)
		end
	end

	def schema_bin(*args)
		bin_path = File.expand_path("#{File.dirname(__FILE__)}/../../bin/#{bin('schema')}")
		`"#{bin_path}" #{args.map { |a| "'#{a}'" }.join(' ')}`
	end

	def primary_key(db, table)
		table = table.to_sym.identifier unless table.kind_of?(Sequel::SQL::Identifier)
		if db.respond_to?(:primary_key)
			db.primary_key(table)
		else
			db.schema(table).select { |c| c[1][:primary_key] }.map { |c| c.first.to_sym }
		end
	end

	def single_integer_primary_key(db, table)
		table = table.to_sym.identifier unless table.kind_of?(Sequel::SQL::Identifier)
		keys = db.schema(table).select { |c| c[1][:primary_key] and c[1][:type] == :integer }
		not keys.nil? and keys.size == 1
	end

	def order_by(db, table)
		pkey = primary_key(db, table)
		if pkey
			pkey.kind_of?(Array) ? pkey : [pkey.to_sym]
		else
			table = table.to_sym.identifier unless table.kind_of?(Sequel::SQL::Identifier)
			db[table].columns
		end
	end
end
end
