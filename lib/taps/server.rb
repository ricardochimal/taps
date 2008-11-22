require 'rubygems'
require 'sinatra'
require 'sequel'
require 'json'

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

	schema = session.connection.schema
	tables = session.connection.tables

	res = schema.keys.select { |k| tables.include? k }.inject({}) { |a,k| a[k] = schema[k]; a }

	res.to_json
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

get '/sessions/:key/:table' do
	session = DbSession.filter(:key => params[:key]).first
	stop 404 unless session

	page = params[:page].to_i
	page = 1 if page < 1

	db = session.connection
	table = db[params[:table].to_sym]
	columns = table.columns
	order = columns.include?(:id) ? :id : columns.first
	rows = table.order(order).paginate(page, ChunkSize).all

	rows.to_json
end

delete '/sessions/:key' do
	session = DbSession.filter(:key => params[:key]).first
	stop 404 unless session

	session.disconnect
	session.destroy

	"ok"
end

