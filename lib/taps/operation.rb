require 'rest_client'
require 'sequel'
require 'zlib'

require 'taps/progress_bar'
require 'taps/config'
require 'taps/utils'
require 'taps/data_stream'
require 'taps/errors'

# disable warnings, rest client makes a lot of noise right now
$VERBOSE = nil

module Taps

class Operation
  attr_reader :database_url, :remote_url, :opts
  attr_reader :session_uri

  def initialize(database_url, remote_url, opts={})
    @database_url = database_url
    @remote_url = remote_url
    @opts = opts
    @exiting = false
    @session_uri = opts[:session_uri]
  end

  def file_prefix
    "op"
  end

  def skip_schema?
    !!opts[:skip_schema]
  end

  def indexes_first?
    !!opts[:indexes_first]
  end

  def table_filter
    opts[:table_filter]
  end

  def exclude_tables
    opts[:exclude_tables] || []
  end

  def apply_table_filter(tables)
    return tables unless table_filter || exclude_tables

    re = table_filter ? Regexp.new(table_filter) : nil
    if tables.kind_of?(Hash)
      ntables = {}
      tables.each do |t, d|
        if !exclude_tables.include?(t.to_s) && (!re || !re.match(t.to_s).nil?)
          ntables[t] = d
        end
      end
      ntables
    else
      tables.reject { |t| exclude_tables.include?(t.to_s) || (re && re.match(t.to_s).nil?) }
    end
  end

  def log
    Taps.log
  end

  def store_session
    file = "#{file_prefix}_#{Time.now.strftime("%Y%m%d%H%M")}.dat"
    puts "\nSaving session to #{file}.."
    File.open(file, 'w') do |f|
      f.write(OkJson.encode(to_hash))
    end
  end

  def to_hash
    {
      :klass => self.class.to_s,
      :database_url => database_url,
      :remote_url => remote_url,
      :session_uri => session_uri,
      :stream_state => stream_state,
      :completed_tables => completed_tables,
      :table_filter => table_filter,
    }
  end

  def exiting?
    !!@exiting
  end

  def setup_signal_trap
    trap("INT") {
      puts "\nCompleting current action..."
      @exiting = true
    }

    trap("TERM") {
      puts "\nCompleting current action..."
      @exiting = true
    }
  end

  def resuming?
    opts[:resume] == true
  end

  def default_chunksize
    opts[:default_chunksize]
  end

  def completed_tables
    opts[:completed_tables] ||= []
  end

  def stream_state
    opts[:stream_state] ||= {}
  end

  def stream_state=(val)
    opts[:stream_state] = val
  end

  def compression_disabled?
    !!opts[:disable_compression]
  end

  def db
    @db ||= Sequel.connect(database_url)
  end

  def server
    @server ||= RestClient::Resource.new(remote_url)
  end

  def session_resource
    @session_resource ||= begin
      @session_uri ||= server['sessions'].post('', http_headers).to_s
      server[@session_uri]
    end
  end

  def set_session(uri)
    session_uri = uri
    @session_resource = server[session_uri]
  end

  def close_session
    @session_resource.delete(http_headers) if @session_resource
  end

  def safe_url(url)
    url.sub(/\/\/(.+?)?:(.*?)@/, '//\1:[hidden]@')
  end

  def safe_remote_url
    safe_url(remote_url)
  end

  def safe_database_url
    safe_url(database_url)
  end

  def http_headers(extra = {})
    base = { :taps_version => Taps.version }
    if compression_disabled?
      base[:accept_encoding] = ""
    else
      base[:accept_encoding] = "gzip, deflate"
    end
    base.merge(extra)
  end

  def format_number(num)
    num.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
  end

  def verify_server
    begin
      server['/'].get(http_headers)
    rescue RestClient::RequestFailed => e
      if e.http_code == 417
        puts "#{safe_remote_url} is running a different minor version of taps."
        puts "#{e.response.to_s}"
        exit(1)
      else
        raise
      end
    rescue RestClient::Unauthorized
      puts "Bad credentials given for #{safe_remote_url}"
      exit(1)
    rescue Errno::ECONNREFUSED
      puts "Can't connect to #{safe_remote_url}. Please check that it's running"
      exit(1)
    end
  end

  def catch_errors(&blk)
    verify_server

    begin
      blk.call
      close_session
    rescue RestClient::Exception, Taps::BaseError => e
      store_session
      if e.kind_of?(Taps::BaseError)
        puts "!!! Caught Server Exception"
        puts "#{e.class}: #{e.message}"
        puts "\n#{e.original_backtrace}" if e.original_backtrace
        exit(1)
      elsif e.respond_to?(:response)
        puts "!!! Caught Server Exception"
        puts "HTTP CODE: #{e.http_code}"
        puts "#{e.response.to_s}"
        exit(1)
      else
        raise
      end
    end
  end

  def self.factory(type, database_url, remote_url, opts)
    type = :resume if opts[:resume]
    klass = case type
      when :pull then Taps::Pull
      when :push then Taps::Push
      when :resume then eval(opts[:klass])
      else raise "Unknown Operation Type -> #{type}"
    end

    klass.new(database_url, remote_url, opts)
  end
end

class Pull < Operation
  def file_prefix
    "pull"
  end

  def to_hash
    super.merge(:remote_tables_info => remote_tables_info)
  end

  def run
    catch_errors do
      unless resuming?
        pull_schema if !skip_schema?
        pull_indexes if indexes_first? && !skip_schema?
      end
      setup_signal_trap
      pull_partial_data if resuming?
      pull_data
      pull_indexes if !indexes_first? && !skip_schema?
      pull_reset_sequences
    end
  end

  def pull_schema
    puts "Receiving schema"

    progress = ProgressBar.new('Schema', tables.size)
    tables.each do |table_name, count|
      schema_data = session_resource['pull/schema'].post({:table_name => table_name}, http_headers).to_s
      log.debug "Table: #{table_name}\n#{schema_data}\n"
      output = Taps::Utils.load_schema(database_url, schema_data)
      puts output if output
      progress.inc(1)
    end
    progress.finish
  end

  def pull_data
    puts "Receiving data"

    puts "#{tables.size} tables, #{format_number(record_count)} records"

    tables.each do |table_name, count|
      progress = ProgressBar.new(table_name.to_s, count)
      stream = Taps::DataStream.factory(db, {
        :chunksize => default_chunksize,
        :table_name => table_name
      })
      pull_data_from_table(stream, progress)
    end
  end

  def pull_partial_data
    return if stream_state == {}

    table_name = stream_state[:table_name]
    record_count = tables[table_name.to_s]
    puts "Resuming #{table_name}, #{format_number(record_count)} records"

    progress = ProgressBar.new(table_name.to_s, record_count)
    stream = Taps::DataStream.factory(db, stream_state)
    pull_data_from_table(stream, progress)
  end

  def pull_data_from_table(stream, progress)
    loop do
      begin
        if exiting?
          store_session
          exit 0
        end

        size = stream.fetch_remote(session_resource['pull/table'], http_headers)
        break if stream.complete?
        progress.inc(size) unless exiting?
        stream.error = false
        self.stream_state = stream.to_hash
      rescue Taps::CorruptedData => e
        puts "Corrupted Data Received #{e.message}, retrying..."
        stream.error = true
        next
      end
    end

    progress.finish
    completed_tables << stream.table_name.to_s
    self.stream_state = {}
  end

  def tables
    h = {}
    remote_tables_info.each do |table_name, count|
      next if completed_tables.include?(table_name.to_s)
      h[table_name.to_s] = count
    end
    h
  end

  def record_count
    @record_count ||= remote_tables_info.values.inject(0) { |a,c| a += c }
  end

  def remote_tables_info
    opts[:remote_tables_info] ||= fetch_remote_tables_info
  end

  def fetch_remote_tables_info
    retries = 0
    max_retries = 10
    begin
      tables = OkJson.decode(session_resource['pull/table_names'].get(http_headers).to_s)
    rescue RestClient::Exception
      retries += 1
      retry if retries <= max_retries
      puts "Unable to fetch tables information from #{remote_url}. Please check the server log."
      exit(1)
    end

    data = {}
    apply_table_filter(tables).each do |table_name|
      retries = 0
      begin
        count = session_resource['pull/table_count'].post({:table => table_name}, http_headers).to_s.to_i
        data[table_name] = count
      rescue RestClient::Exception
        retries += 1
        retry if retries <= max_retries
        puts "Unable to fetch tables information from #{remote_url}. Please check the server log."
        exit(1)
      end
    end
    data
  end

  def pull_indexes
    puts "Receiving indexes"

    idxs = OkJson.decode(session_resource['pull/indexes'].get(http_headers).to_s)

    apply_table_filter(idxs).each do |table, indexes|
      next unless indexes.size > 0
      progress = ProgressBar.new(table, indexes.size)
      indexes.each do |idx|
        output = Taps::Utils.load_indexes(database_url, idx)
        puts output if output
        progress.inc(1)
      end
      progress.finish
    end
  end

  def pull_reset_sequences
    puts "Resetting sequences"

    output = Taps::Utils.schema_bin(:reset_db_sequences, database_url)
    puts output if output
  end
end

class Push < Operation
  def file_prefix
    "push"
  end

  def to_hash
    super.merge(:local_tables_info => local_tables_info)
  end

  def run
    catch_errors do
      unless resuming?
        push_schema if !skip_schema?
        push_indexes if indexes_first? && !skip_schema?
      end
      setup_signal_trap
      push_partial_data if resuming?
      push_data
      push_indexes if !indexes_first? && !skip_schema?
      push_reset_sequences
    end
  end

  def push_indexes
    idxs = OkJson.decode(Taps::Utils.schema_bin(:indexes_individual, database_url))

    return unless idxs.size > 0

    puts "Sending indexes"

    apply_table_filter(idxs).each do |table, indexes|
      next unless indexes.size > 0
      progress = ProgressBar.new(table, indexes.size)
      indexes.each do |idx|
        session_resource['push/indexes'].post(idx, http_headers)
        progress.inc(1)
      end
      progress.finish
    end
  end

  def push_schema
    puts "Sending schema"

    progress = ProgressBar.new('Schema', tables.size)
    tables.each do |table, count|
      schema_data = Taps::Utils.schema_bin(:dump_table, database_url, table)
      log.debug "Table: #{table}\n#{schema_data}\n"
      session_resource['push/schema'].post(schema_data, http_headers)
      progress.inc(1)
    end
    progress.finish
  end

  def push_reset_sequences
    puts "Resetting sequences"

    session_resource['push/reset_sequences'].post('', http_headers)
  end

  def push_partial_data
    return if stream_state == {}

    table_name = stream_state[:table_name]
    record_count = tables[table_name.to_s]
    puts "Resuming #{table_name}, #{format_number(record_count)} records"
    progress = ProgressBar.new(table_name.to_s, record_count)
    stream = Taps::DataStream.factory(db, stream_state)
    push_data_from_table(stream, progress)
  end

  def push_data
    puts "Sending data"

    puts "#{tables.size} tables, #{format_number(record_count)} records"

    tables.each do |table_name, count|
      stream = Taps::DataStream.factory(db,
        :table_name => table_name,
        :chunksize => default_chunksize)
      progress = ProgressBar.new(table_name.to_s, count)
      push_data_from_table(stream, progress)
    end
  end

  def push_data_from_table(stream, progress)
    loop do
      if exiting?
        store_session
        exit 0
      end

      row_size = 0
      chunksize = stream.state[:chunksize]

      begin
        chunksize = Taps::Utils.calculate_chunksize(chunksize) do |c|
          stream.state[:chunksize] = c.to_i
          encoded_data, row_size, elapsed_time = nil
          d1 = c.time_delta do
            encoded_data, row_size, elapsed_time = stream.fetch
          end
          break if stream.complete?

          data = nil
          d2 = c.time_delta do
            data = {
              :state => stream.to_hash,
              :checksum => Taps::Utils.checksum(encoded_data).to_s
            }
          end

          begin
            content, content_type = nil
            d3 = c.time_delta do
              content, content_type = Taps::Multipart.create do |r|
                r.attach :name => :encoded_data,
                  :payload => encoded_data,
                  :content_type => 'application/octet-stream'
                r.attach :name => :json,
                  :payload => OkJson.encode(data),
                  :content_type => 'application/json'
              end
            end
            session_resource['push/table'].post(content, http_headers(:content_type => content_type))
            self.stream_state = stream.to_hash
          rescue => e
            Taps::Utils.reraise_server_exception(e)
          end

          c.idle_secs = (d1 + d2 + d3)

          elapsed_time
        end
      rescue Taps::CorruptedData => e
        # retry the same data, it got corrupted somehow.
        next
      rescue Taps::DuplicatePrimaryKeyError => e
        # verify the stream and retry it
        stream = stream.verify_remote_stream(session_resource['push/verify_stream'], http_headers)
        next
      end
      stream.state[:chunksize] = chunksize

      progress.inc(row_size)

      stream.increment(row_size)
      break if stream.complete?
    end

    progress.finish
    completed_tables << stream.table_name.to_s
    self.stream_state = {}
  end

  def local_tables_info
    opts[:local_tables_info] ||= fetch_local_tables_info
  end

  def tables
    h = {}
    local_tables_info.each do |table_name, count|
      next if completed_tables.include?(table_name.to_s)
      h[table_name.to_s] = count
    end
    h
  end

  def record_count
    @record_count ||= local_tables_info.values.inject(0) { |a,c| a += c }
  end

  def fetch_local_tables_info
    tables_with_counts = {}
    db.tables.each do |table|
      tables_with_counts[table] = db[table.to_sym.identifier].count
    end
    apply_table_filter(tables_with_counts)
  end

end

end
