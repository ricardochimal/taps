require 'zlib'
require 'stringio'

module Taps
module Utils
	extend self

	def checksum(data)
		Zlib.crc32(data)
	end

	def valid_data?(data, crc32)
		Zlib.crc32(data) == crc32
	end

	def gzip(data)
		io = StringIO.new
		gz = Zlib::GzipWriter.new(io)
		gz.write data
		gz.close
		io.string.to_s
	end

	def gunzip(gzip_data)
		io = StringIO.new(gzip_data)
		gz = Zlib::GzipReader.new(io)
		data = gz.read
		gz.close
		data
	end
end
end
