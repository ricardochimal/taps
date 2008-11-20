require 'rubygems'
require 'sinatra'
require 'sequel'
require 'json'

configure do
	DB = Sequel.connect('sqlite://remote.db')
end

error do
	e = request.env['sinatra.error']
	puts e.to_s
	puts e.backtrace.join("\n")
	"Application error"
end

post '/sessions/:id/:table' do
	data = JSON.parse request.body.string

	data.each do |row|
		DB[params[:table].to_sym] << row
	end
end


