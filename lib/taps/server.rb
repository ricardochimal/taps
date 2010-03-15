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

	post '/sessions/:key/push/table/:table' do
		session = DbSession.filter(:key => params[:key]).first
		halt 404 unless session

		gzip_data = request.body.read
		halt 412 unless Taps::Utils.valid_data?(gzip_data, request.env['HTTP_TAPS_CHECKSUM'])

		rows = Marshal.load(Taps::Utils.gunzip(gzip_data))

		session.conn do |db|
			table = db[params[:table].to_sym]
			table.import(rows[:header], rows[:data])
		end

		"#{rows[:data].size}"
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

		gzip_data = nil
		stream = nil

		session.conn do |db|
			state = JSON.parse(params[:state]).symbolize_keys
			stream = Taps::DataStream.factory(db, state)
			gzip_data = stream.fetch.first
		end

		checksum = Taps::Utils.checksum(gzip_data).to_s
		json = { :checksum => checksum, :state => stream.to_hash }.to_json

		content, content_type_value = Taps::Multipart.create({
			:gzip_data => Taps::Multipart.new({
				:payload => gzip_data,
				:content_type => 'application/octet-stream',
			}),
			:json => Taps::Multipart.new({
				:payload => json,
				:content_type => 'application/json'
			})
		})

		content_type content_type_value
		content
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
