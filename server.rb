require 'rubygems'
require 'sinatra'
require 'sequel'
require 'json'

require '/home/adam/rush/lib/rush'

configure do
	dir = Rush.dir(__FILE__)
	dir['remote.db'].destroy
	dir['empty.db'].duplicate 'remote.db'
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

	$connections ||= {}
	$connections[key] = Sequel.connect('sqlite://local.db')

	"/sessions/#{key}"
end

post '/sessions/:key/:table' do
	db = $connections[params[:key]]
	stop 404 unless db

	data = JSON.parse request.body.string

	data.each do |row|
		db[params[:table].to_sym] << row
	end
end

delete '/sessions/:key' do
	db = $connections[params[:key]]
	stop 404 unless db

	db.disconnect
	$connections.delete params[:key]
	"ok"
end

