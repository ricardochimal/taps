require 'rubygems'
require 'sinatra'
require 'sequel'
require 'json'

require '/home/adam/rush/lib/rush'

configure do
	dir = Rush.dir(__FILE__)
	dir['remote.db'].destroy
	dir['empty.db'].duplicate 'remote.db'

	DB = Sequel.connect('sqlite://remote.db')
end

error do
	e = request.env['sinatra.error']
	puts e.to_s
	puts e.backtrace.join("\n")
	"Application error"
end

post '/sessions' do
	puts "=== Starting session"
	"1"
end

post '/sessions/:id/:table' do
	data = JSON.parse request.body.string
	puts "Received #{data.size} records"

	puts data.inspect

	data.each do |row|
		DB[params[:table].to_sym] << row
	end
end

delete '/sessions/:id' do
	puts "--- Ending session"
	"ok"
end

