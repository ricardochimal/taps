require 'sinatra/base'
require 'taps/config'
require 'taps/utils'
require 'taps/db_session'
require 'taps/data_stream'

module Taps
class Server < Sinatra::Base
  use Rack::Auth::Basic do |login, password|
    login == Taps::Config.login && password == Taps::Config.password
  end

  use Rack::Deflater unless ENV['NO_DEFLATE']

  set :raise_errors => false
  set :show_exceptions => false

  error do
    e = request.env['sinatra.error']
    puts "ERROR: #{e.class}: #{e.message}"
    begin
      require 'hoptoad_notifier'
      HoptoadNotifier.configure do |config|
        config.api_key = ENV["HOPTOAD_API_KEY"]
      end
      HoptoadNotifier.notify(e)
      puts "  notified Hoptoad"
    rescue LoadError
      puts "An error occurred but Hoptoad was not notified. To use Hoptoad, please"
      puts "install the 'hoptoad_notifier' gem and set ENV[\"HOPTOAD_API_KEY\"]"
    end
    if e.kind_of?(Taps::BaseError)
      content_type "application/json"
      halt 412, ::OkJson.encode({ 'error_class' => e.class.to_s, 'error_message' => e.message, 'error_backtrace' => e.backtrace.join("\n") })
    else
      "Taps Server Error: #{e}\n#{e.backtrace}"
    end
  end

  before do
    unless request.path_info == '/health'
      major, minor, patch = request.env['HTTP_TAPS_VERSION'].split('.') rescue []
      unless "#{major}.#{minor}" == Taps.compatible_version #&& patch.to_i >= 23
        halt 417, "Taps >= v#{Taps.compatible_version}.x is required for this server"
      end
    end
  end

  get '/health' do
    content_type 'application/json'
    ::OkJson.encode({ :ok => true })
  end

  get '/' do
    "hello"
  end

  post '/sessions' do
    key = rand(9999999999).to_s

    if ENV['NO_DEFAULT_DATABASE_URL']
      database_url = request.body.string
    else
      database_url = Taps::Config.database_url || request.body.string
    end

    DbSession.create(:key => key, :database_url => database_url, :started_at => Time.now, :last_access => Time.now)

    "/sessions/#{key}"
  end

  post '/sessions/:key/push/verify_stream' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    state = DataStream.parse_json(params[:state])
    stream = nil

    size = 0
    session.conn do |db|
      Taps::Utils.server_error_handling do
        stream = DataStream.factory(db, state)
        stream.verify_stream
      end
    end

    content_type 'application/json'
    ::OkJson.encode({ :state => stream.to_hash })
  end

  post '/sessions/:key/push/table' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    json = DataStream.parse_json(params[:json])

    size = 0
    session.conn do |db|
      Taps::Utils.server_error_handling do
        stream = DataStream.factory(db, json[:state])
        size = stream.fetch_remote_in_server(params)
      end
    end

    # TODO: return the stream's state with the size
    size.to_s
  end

  post '/sessions/:key/push/reset_sequences' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    Taps::Utils.schema_bin(:reset_db_sequences, session.database_url)
  end

  post '/sessions/:key/push/schema' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    schema_data = request.body.read
    Taps::Utils.load_schema(session.database_url, schema_data)
  end

  post '/sessions/:key/push/indexes' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    index_data = request.body.read
    Taps::Utils.load_indexes(session.database_url, index_data)
  end

  post '/sessions/:key/pull/schema' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    Taps::Utils.schema_bin(:dump_table, session.database_url, params[:table_name])
  end

  get '/sessions/:key/pull/indexes' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    content_type 'application/json'
    Taps::Utils.schema_bin(:indexes_individual, session.database_url)
  end

  get '/sessions/:key/pull/table_names' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    tables = []
    session.conn do |db|
      tables = db.tables
    end

    content_type 'application/json'
    ::OkJson.encode(tables)
  end

  post '/sessions/:key/pull/table_count' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    count = 0
    session.conn do |db|
      count = db[ params[:table].to_sym.identifier ].count
    end
    count.to_s
  end

  post '/sessions/:key/pull/table' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    encoded_data = nil
    stream = nil

    session.conn do |db|
      state = ::OkJson.decode(params[:state]).symbolize_keys
      stream = Taps::DataStream.factory(db, state)
      encoded_data = stream.fetch.first
    end

    checksum = Taps::Utils.checksum(encoded_data).to_s
    json = ::OkJson.encode({ :checksum => checksum, :state => stream.to_hash })

    content, content_type_value = Taps::Multipart.create do |r|
      r.attach :name => :encoded_data,
        :payload => encoded_data,
        :content_type => 'application/octet-stream'
      r.attach :name => :json,
        :payload => json,
        :content_type => 'application/json'
    end

    content_type content_type_value
    content
  end

  delete '/sessions/:key' do
    session = DbSession.filter(:key => params[:key]).first
    halt 404 unless session

    session.destroy

    "ok"
  end

end
end
