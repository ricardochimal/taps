require File.dirname(__FILE__) + '/base'
require 'taps/utils'

describe Taps::Utils do
  it 'generates a checksum using crc32' do
    Taps::Utils.checksum('hello world').should == Zlib.crc32('hello world')
  end

  it 'formats a data hash into one hash that contains an array of headers and an array of array of data' do
    first_row = { x: 1, y: 1 }
    first_row.stubs(:keys).returns(%i[x y])
    Taps::Utils.format_data([first_row, { x: 2, y: 2 }]).should == { header: %i[x y], data: [[1, 1], [2, 2]] }
  end

  it 'enforces length limitations on columns' do
    data = [{ a: 'aaabbbccc' }]
    schema = [[:a, { db_type: 'varchar(3)' }]]
    -> { Taps::Utils.format_data(data, schema: schema) }.should.raise(Taps::InvalidData)
  end

  it 'returns a list of columns that are text fields if the database is mysql' do
    @db = mock('db', url: 'mysql://localhost/mydb')
    @db.stubs(:schema).with(:mytable).returns([
                                                [:id, { db_type: 'int' }],
                                                [:mytext, { db_type: 'text' }]
                                              ])
    Taps::Utils.incorrect_blobs(@db, :mytable).should == [:mytext]
  end

  it 'rejects a multiple-column primary key as a single integer primary key' do
    @db = mock('db')
    @db.stubs(:schema).with(:pktable.identifier).returns([
                                                           [:id1, { primary_key: true, type: :integer }],
                                                           [:id2, { primary_key: true, type: :string }]
                                                         ])
    Taps::Utils.single_integer_primary_key(@db, :pktable).should.be.false
  end
end
