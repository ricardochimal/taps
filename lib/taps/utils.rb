require 'zlib'
require 'stringio'

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
end
end
