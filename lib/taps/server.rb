require 'sinatra/base'
require 'taps/config'
require 'taps/utils'
require 'taps/db_session'

module Taps
class Server < Sinatra::Default
	use Rack::Auth::Basic do |login, password|
		login == Taps::Config.login && password == Taps::Config.password
	end

	error do
		e = request.env['sinatra.error']
		"Taps Server Error: #{e}"
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
		database_url = Taps::Config.database_url || request.body.string

		DbSession.create(:key => key, :database_url => database_url, :started_at => Time.now, :last_access => Time.now)

		"/sessions/#{key}"
	end

	post '/sessions/:key/tables/:table' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		gzip_data = request.body.read
		halt 412 unless Taps::Utils.valid_data?(gzip_data, request.env['HTTP_TAPS_CHECKSUM'])

		rows = Marshal.load(Taps::Utils.gunzip(gzip_data))

		db = session.connection
		table = db[params[:table].to_sym]
		table.import(rows[:header], rows[:data])

		"#{rows[:data].size}"
	end

	post '/sessions/:key/reset_sequences' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		schema_app = File.dirname(__FILE__) + '/../../bin/schema'
		Taps::Utils.schema_bin(:reset_db_sequences, session.database_url)
	end

	post '/sessions/:key/schema' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		schema_data = request.body.read
		Taps::Utils.load_schema(session.database_url, schema_data)
	end

	post '/sessions/:key/indexes' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		index_data = request.body.read
		Taps::Utils.load_indexes(session.database_url, index_data)
	end

	get '/sessions/:key/schema' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		schema_app = File.dirname(__FILE__) + '/../../bin/schema'
		Taps::Utils.schema_bin(:dump, session.database_url)
	end

	get '/sessions/:key/indexes' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		schema_app = File.dirname(__FILE__) + '/../../bin/schema'
		Taps::Utils.schema_bin(:indexes, session.database_url)
	end

	get '/sessions/:key/tables' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		db = session.connection
		tables = db.tables

		tables_with_counts = tables.inject({}) do |accum, table|
			accum[table] = db[table].count
			accum
		end

		Marshal.dump(tables_with_counts)
	end

	get '/sessions/:key/tables/:table/:chunk' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		chunk = params[:chunk].to_i
		chunk = 500 if chunk < 1

		offset = params[:offset].to_i
		offset = 0 if offset < 0

		db = session.connection
		table = db[params[:table].to_sym]
		order = Taps::Utils.order_by(db, params[:table].to_sym)
		string_columns = Taps::Utils.incorrect_blobs(db, params[:table].to_sym)
		raw_data = Marshal.dump(Taps::Utils.format_data(table.order(*order).limit(chunk, offset).all, string_columns))
		gzip_data = Taps::Utils.gzip(raw_data)
		response['Taps-Checksum'] = Taps::Utils.checksum(gzip_data).to_s
		response['Content-Type'] = "application/octet-stream"
		gzip_data
	end

	delete '/sessions/:key' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		session.disconnect
		session.destroy

		"ok"
	end

end
end
