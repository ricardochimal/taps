require File.dirname(__FILE__) + '/base'
require 'taps/data_stream'

describe Taps::DataStream do
  before do
    @db = mock('db')
  end

  it "increments the offset" do
    stream = Taps::DataStream.new(@db, :table_name => 'test_table', :chunksize => 100)
    stream.state[:offset].should == 0
    stream.increment(100)
    stream.state[:offset].should == 100
  end

  it "marks the stream complete if no rows are fetched" do
    stream = Taps::DataStream.new(@db, :table_name => 'test_table', :chunksize => 100)
    stream.stubs(:fetch_rows).returns({})
    stream.complete?.should.be.false
    stream.fetch
    stream.complete?.should.be.true
  end
end
