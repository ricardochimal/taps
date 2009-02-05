require 'zlib'
require 'stringio'
require 'time'
require 'tempfile'

module Taps
module Utils
	extend self

	def checksum(data)
		Zlib.crc32(data)
	end

	def valid_data?(data, crc32)
		Zlib.crc32(data) == crc32.to_i
	end

	def gzip(data)
		io = StringIO.new
		gz = Zlib::GzipWriter.new(io)
		gz.write data
		gz.close
		io.string
	end

	def gunzip(gzip_data)
		io = StringIO.new(gzip_data)
		gz = Zlib::GzipReader.new(io)
		data = gz.read
		gz.close
		data
	end

	def format_data(data)
		return {} if data.size == 0
		header = data[0].keys
		only_data = data.collect do |row|
			header.collect { |h| row[h] }
		end
		{ :header => header, :data => only_data }
	end

	def calculate_chunksize(old_chunksize)
		t1 = Time.now
		yield
		t2 = Time.now

		diff = t2 - t1
		new_chunksize = if diff > 3.0
			(old_chunksize / 3).ceil
		elsif diff > 1.1
			old_chunksize - 100
		elsif diff < 0.8
			old_chunksize * 2
		else
			old_chunksize + 100
		end
		new_chunksize = 100 if new_chunksize < 100
		new_chunksize
	end

	def load_schema(database_url, schema_data)
		Tempfile.open('taps') do |tmp|
			File.open(tmp.path, 'w') { |f| f.write(schema_data) }
			`#{File.dirname(__FILE__)}/../../bin/schema load #{database_url} #{tmp.path}`
		end
	end
end
end
