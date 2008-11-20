require 'rubygems'
require 'sinatra'

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
	system "ruby spinoff.rb -p 5000 &"
	sleep 2
	"1"
end

post '/sessions/:id/:table' do
	"wrong server"
end

delete '/sessions/:id' do
	"ok"
end

