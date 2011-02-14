require File.dirname(__FILE__) + '/base'
require 'taps/operation'

describe Taps::Operation do
  before do
    @op = Taps::Operation.new('dummy://localhost', 'http://x:y@localhost:5000')
  end

  it "returns an array of tables that match the regex table_filter" do
    @op = Taps::Operation.new('dummy://localhost', 'http://x:y@localhost:5000', :table_filter => 'abc')
    @op.apply_table_filter(['abc', 'def']).should == ['abc']
  end

  it "returns a hash of tables that match the regex table_filter" do
    @op = Taps::Operation.new('dummy://localhost', 'http://x:y@localhost:5000', :table_filter => 'abc')
    @op.apply_table_filter({ 'abc' => 1, 'def' => 2 }).should == { 'abc' => 1 }
  end

  it "returns an array of tables without the exclude_tables tables" do
    @op = Taps::Operation.new('dummy://localhost', 'http://x:y@localhost:5000', :exclude_tables => ['abc', 'ghi', 'jkl'])
    @op.apply_table_filter(['abc', 'def', 'ghi', 'jkl', 'mno']).should == ['def', 'mno']
  end

  it "returns a hash of tables without the exclude_tables tables" do
    @op = Taps::Operation.new('dummy://localhost', 'http://x:y@localhost:5000', :exclude_tables => ['abc', 'ghi', 'jkl'])
    @op.apply_table_filter({ 'abc' => 1, 'def' => 2, 'ghi' => 3, 'jkl' => 4, 'mno' => 5 }).should == { 'def' => 2, 'mno' => 5 }
  end

  it "masks a url's password" do
    @op.safe_url("mysql://root:password@localhost/mydb").should == "mysql://root:[hidden]@localhost/mydb"
  end

  it "returns http headers with compression enabled" do
    @op.http_headers.should == { :taps_version => Taps.version, :accept_encoding => "gzip, deflate" }
  end

  it "returns http headers with compression disabled" do
    @op.stubs(:compression_disabled?).returns(true)
    @op.http_headers.should == { :taps_version => Taps.version, :accept_encoding => "" }
  end

end
