require File.dirname(__FILE__) + '/base'
require 'taps/operation'

describe Taps::Operation do
	before do
	end

	it "returns an array of tables that match the regex table_filter" do
		@op = Taps::Operation.new('dummy://localhost', 'http://x:y@localhost:5000', :table_filter => 'abc')
		@op.apply_table_filter(['abc', 'def']).should == ['abc']
	end

	it "returns a hash of tables that match the regex table_filter" do
		@op = Taps::Operation.new('dummy://localhost', 'http://x:y@localhost:5000', :table_filter => 'abc')
		@op.apply_table_filter({ 'abc' => 1, 'def' => 2 }).should == { 'abc' => 1 }
	end
end

