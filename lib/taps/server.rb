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

	error do
		e = request.env['sinatra.error']
		"Taps Server Error: #{e}\n#{e.backtrace}"
	end

	before do
		major, minor, patch = request.env['HTTP_TAPS_VERSION'].split('.') rescue []
		unless "#{major}.#{minor}" == Taps.compatible_version
			halt 417, "Taps v#{Taps.compatible_version}.x is required for this server"
		end
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

	post '/sessions/:key/push/table' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		json = DataStream.parse_json(params[:json])

		size = 0
		session.conn do |db|
			begin
				stream = DataStream.factory(db, json[:state])
				size = stream.fetch_remote_in_server(params)
			rescue Taps::DataStream::CorruptedData
				halt 412
			end
		end

		# TODO: return the stream's state with the size
		size.to_s
	end

	post '/sessions/:key/push/reset_sequences' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		schema_app = File.dirname(__FILE__) + '/../../bin/schema'
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

	get '/sessions/:key/pull/schema' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		schema_app = File.dirname(__FILE__) + '/../../bin/schema'
		Taps::Utils.schema_bin(:dump, session.database_url)
	end

	get '/sessions/:key/pull/indexes' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		schema_app = File.dirname(__FILE__) + '/../../bin/schema'
		Taps::Utils.schema_bin(:indexes, session.database_url)
	end

	get '/sessions/:key/pull/tables' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		tables_with_counts = nil
		session.conn do |db|
			tables = db.tables
			tables_with_counts = tables.inject({}) do |accum, table|
				accum[table] = db[table].count
				accum
			end
		end

		Marshal.dump(tables_with_counts)
	end

	post '/sessions/:key/pull/table' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		encoded_data = nil
		stream = nil

		session.conn do |db|
			state = JSON.parse(params[:state]).symbolize_keys
# 			puts state.inspect
			stream = Taps::DataStream.factory(db, state)
			encoded_data = stream.fetch.first
		end

		checksum = Taps::Utils.checksum(encoded_data).to_s
		json = { :checksum => checksum, :state => stream.to_hash }.to_json

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
