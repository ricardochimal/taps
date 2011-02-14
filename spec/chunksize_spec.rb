require File.dirname(__FILE__) + '/base'
require 'taps/utils'

describe Taps::Chunksize do
  it "scales chunksize down slowly when the time delta of the block is just over a second" do
    Time.stubs(:now).returns(10.0).returns(11.5)
    Taps::Utils.calculate_chunksize(1000) { |c| }.should == 900
  end

  it "scales chunksize down fast when the time delta of the block is over 3 seconds" do
    Time.stubs(:now).returns(10.0).returns(15.0)
    Taps::Utils.calculate_chunksize(3000) { |c| }.should == 1000
  end

  it "scales up chunksize fast when the time delta of the block is under 0.8 seconds" do
    Time.stubs(:now).returns(10.0).returns(10.7)
    Taps::Utils.calculate_chunksize(1000) { |c| }.should == 2000
  end

  it "scales up chunksize slow when the time delta of the block is between 0.8 and 1.1 seconds" do
    Time.stubs(:now).returns(10.0).returns(10.8)
    Taps::Utils.calculate_chunksize(1000) { |c| }.should == 1100

    Time.stubs(:now).returns(10.0).returns(11.1)
    Taps::Utils.calculate_chunksize(1000) { |c| }.should == 1100
  end

  it "will reset the chunksize to a small value if we got a broken pipe exception" do
    Taps::Utils.calculate_chunksize(1000) do |c|
      raise Errno::EPIPE if c.chunksize == 1000
      c.chunksize.should == 10
    end.should == 10
  end

  it "will reset the chunksize to a small value if we got a broken pipe exception a second time" do
    Taps::Utils.calculate_chunksize(1000) do |c|
      raise Errno::EPIPE if c.chunksize == 1000 || c.chunksize == 10
      c.chunksize.should == 1
    end.should == 1
  end
end
