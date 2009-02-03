require File.dirname(__FILE__) + '/base'
require File.dirname(__FILE__) + '/../lib/taps/utils'

describe Taps::Utils do
	it "gunzips a string" do
		@hello_world = "\037\213\b\000R\261\207I\000\003\313H\315\311\311W(\317/\312I\001\000\205\021J\r\v\000\000\000"
		Taps::Utils.gunzip(@hello_world).should == "hello world"
	end

	it "gzips and gunzips a string and returns the same string" do
		Taps::Utils.gunzip(Taps::Utils.gzip("hello world")).should == "hello world"
	end

	it "generates a checksum using crc32" do
		Taps::Utils.checksum("hello world").should == Zlib.crc32("hello world")
	end

	it "formats a data hash into one hash that contains an array of headers and an array of array of data" do
		Taps::Utils.format_data([ { :x => 1, :y => 1 }, { :x => 2, :y => 2 } ]).should == { :header => [ :x, :y ], :data => [ [1, 1], [2, 2] ] }
	end
end

