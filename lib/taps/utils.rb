require 'zlib'
require 'stringio'
require 'time'
require 'tempfile'
require 'rest_client'

require 'taps/errors'
require 'taps/chunksize'

module Taps
module Utils
  extend self

  def windows?
    return @windows if defined?(@windows)
    require 'rbconfig'
    @windows = !!(RbConfig::CONFIG['host_os'] =~ /mswin|mingw/)
  end

  def bin(cmd)
    cmd = "#{cmd}.cmd" if windows?
    cmd
  end

  def checksum(data)
    Zlib.crc32(data)
  end

  def valid_data?(data, crc32)
    Zlib.crc32(data) == crc32.to_i
  end

  def base64encode(data)
    [data].pack("m")
  end

  def base64decode(data)
    data.unpack("m").first
  end

  def format_data(data, opts={})
    return {} if data.size == 0
    string_columns = opts[:string_columns] || []
    schema = opts[:schema] || []
    table  = opts[:table]

    max_lengths = schema.inject({}) do |hash, (column, meta)|
      if meta[:db_type] =~ /^varchar\((\d+)\)/
        hash.update(column => $1.to_i)
      end
      hash
    end

    header = data[0].keys
    only_data = data.collect do |row|
      row = blobs_to_string(row, string_columns)
      row.each do |column, data|
        if data.to_s.length > (max_lengths[column] || data.to_s.length)
          raise Taps::InvalidData.new(<<-ERROR)
Detected data that exceeds the length limitation of its column. This is
generally due to the fact that SQLite does not enforce length restrictions.

Table  : #{table}
Column : #{column}
Type   : #{schema.detect{|s| s.first == column}.last[:db_type]}
Data   : #{data}
          ERROR
        end
      end
      header.collect { |h| row[h] }
    end
    { :header => header, :data => only_data }
  end

  # mysql text and blobs fields are handled the same way internally
  # this is not true for other databases so we must check if the field is
  # actually text and manually convert it back to a string
  def incorrect_blobs(db, table)
    return [] if (db.url =~ /mysql:\/\//).nil?

    columns = []
    db.schema(table).each do |data|
      column, cdata = data
      columns << column if cdata[:db_type] =~ /text/
    end
    columns
  end

  def blobs_to_string(row, columns)
    return row if columns.size == 0
    columns.each do |c|
      row[c] = row[c].to_s if row[c].kind_of?(Sequel::SQL::Blob)
    end
    row
  end

  def calculate_chunksize(old_chunksize)
    c = Taps::Chunksize.new(old_chunksize)

    begin
      c.start_time = Time.now
      c.time_in_db = yield c
    rescue Errno::EPIPE, RestClient::RequestFailed, RestClient::RequestTimeout
      c.retries += 1
      raise if c.retries > 2

      # we got disconnected, the chunksize could be too large
      # reset the chunksize based on the number of retries
      c.reset_chunksize
      retry
    end

    c.end_time = Time.now
    c.calc_new_chunksize
  end

  def load_schema(database_url, schema_data)
    Tempfile.open('taps') do |tmp|
      File.open(tmp.path, 'w') { |f| f.write(schema_data) }
      schema_bin(:load, database_url, tmp.path)
    end
  end

  def load_indexes(database_url, index_data)
    Tempfile.open('taps') do |tmp|
      File.open(tmp.path, 'w') { |f| f.write(index_data) }
      schema_bin(:load_indexes, database_url, tmp.path)
    end
  end

  def schema_bin(*args)
    bin_path = File.expand_path("#{File.dirname(__FILE__)}/../../bin/#{bin('schema')}")
    `"#{bin_path}" #{args.map { |a| "'#{a}'" }.join(' ')}`
  end

  def primary_key(db, table)
    db.schema(table).select { |c| c[1][:primary_key] }.map { |c| c[0] }
  end

  def single_integer_primary_key(db, table)
    table = table.to_sym.identifier unless table.kind_of?(Sequel::SQL::Identifier)
    keys = db.schema(table).select { |c| c[1][:primary_key] and c[1][:type] == :integer }
    not keys.nil? and keys.size == 1
  end

  def order_by(db, table)
    pkey = primary_key(db, table)
    if pkey
      pkey.kind_of?(Array) ? pkey : [pkey.to_sym]
    else
      table = table.to_sym.identifier unless table.kind_of?(Sequel::SQL::Identifier)
      db[table].columns
    end
  end


  # try to detect server side errors to
  # give the client a more useful error message
  def server_error_handling(&blk)
    begin
      blk.call
    rescue Sequel::DatabaseError => e
      if e.message =~ /duplicate key value/i
        raise Taps::DuplicatePrimaryKeyError, e.message
      else
        raise
      end
    end
  end

  def reraise_server_exception(e)
    if e.kind_of?(RestClient::Exception)
      if e.respond_to?(:response) && e.response.headers[:content_type] == 'application/json'
        json = OkJson.decode(e.response.to_s)
        klass = eval(json['error_class']) rescue nil
        raise klass.new(json['error_message'], :backtrace => json['error_backtrace']) if klass
      end
    end
    raise e
  end
end
end
