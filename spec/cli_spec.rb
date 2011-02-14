require File.dirname(__FILE__) + '/base'
require 'taps/cli'

describe Taps::Cli do
  it "translates a list of tables into a regex that can be used in table_filter" do
    @cli = Taps::Cli.new(["-t", "mytable1,logs", "sqlite://tmp.db", "http://x:y@localhost:5000"])
    opts = @cli.clientoptparse(:pull)
    opts[:table_filter].should == "(^mytable1$|^logs$)"
  end

  it "translates a list of tables to exclude into a regex that can be used in table_filter" do
    @cli = Taps::Cli.new(["-e", "mytable1,logs", "sqlite://tmp.db", "http://x:y@localhost:5000"])
    opts = @cli.clientoptparse(:pull)
    opts[:exclude_tables].should == ['mytable1','logs']
  end
end
