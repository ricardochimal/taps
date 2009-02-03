require 'rubygems'
require 'sinatra'
require 'sequel'
require 'json'
require File.dirname(__FILE__) + '/utils'

use Rack::Auth::Basic do |login, password|
	login == Taps::Config.login && password == Taps::Config.password
end

configure do
	Sequel.connect(ENV['DATABASE_URL'] || 'sqlite:/')

	require File.dirname(__FILE__) + '/db_session'
end

error do
	e = request.env['sinatra.error']
	puts e.to_s
	puts e.backtrace.join("\n")
	"Application error"
end

post '/sessions' do
	# todo: authenticate

	key = rand(9999999999).to_s
	database_url = Sinatra.application.options.database_url || request.body.string

	DbSession.create(:key => key, :database_url => database_url, :started_at => Time.now, :last_access => Time.now)

	"/sessions/#{key}"
end

post '/sessions/:key/:table' do
	session = DbSession.filter(:key => params[:key]).first
	stop 404 unless session

	data = JSON.parse request.body.string

	db = session.connection
	table = db[params[:table].to_sym]

	db.transaction do
		data.each { |row| table << row }
	end

	"#{data.size} records loaded"
end

get '/sessions/:key/schema' do
	session = DbSession.filter(:key => params[:key]).first
	stop 404 unless session

	schema_app = File.dirname(__FILE__) + '/../../bin/schema'
	`#{schema_app} dump #{session.database_url}`
end

get '/sessions/:key/indexes' do
	session = DbSession.filter(:key => params[:key]).first
	stop 404 unless session

	schema_app = File.dirname(__FILE__) + '/../../bin/schema'
	`#{schema_app} indexes #{session.database_url}`
end

get '/sessions/:key/tables' do
	session = DbSession.filter(:key => params[:key]).first
	stop 404 unless session

	db = session.connection
	tables = db.tables

	tables_with_counts = tables.inject({}) do |accum, table|
		accum[table] = db[table].count
		accum
	end

	tables_with_counts.to_json
end

get '/sessions/:key/:table/:chunk' do
	session = DbSession.filter(:key => params[:key]).first
	stop 404 unless session

	chunk = params[:chunk].to_i
	chunk = 500 if chunk < 1

	offset = params[:offset].to_i
	offset = 0 if offset < 0

	db = session.connection
	table = db[params[:table].to_sym]
	columns = table.columns
	order = columns.include?(:id) ? :id : columns.first
	raw_data = Marshal.dump(table.order(order).limit(chunk, offset).all)
	gzip_data = Taps::Utils.gzip(raw_data)
	response['Taps-Checksum'] = Taps::Utils.checksum(gzip_data).to_s
	response['Content-Type'] = "application/octet-stream"
	gzip_data
end

delete '/sessions/:key' do
	session = DbSession.filter(:key => params[:key]).first
	stop 404 unless session

	session.disconnect
	session.destroy

	"ok"
end

