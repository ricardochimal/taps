require 'rubygems'
require 'sinatra'
require 'sequel'
require 'json'

configure do
	Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://sessions.db')

	$LOAD_PATH.unshift(File.dirname(__FILE__) + '/lib')
	require 'session'
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
	database_url = request.body.string

	Session.create(:key => key, :database_url => database_url, :started_at => Time.now, :last_access => Time.now)

	"/sessions/#{key}"
end

post '/sessions/:key/:table' do
	session = Session.filter(:key => params[:key]).first
	stop 404 unless session

	$connections ||= {}
	$connections[session.key] ||= Sequel.connect(session.database_url)
	db = $connections[session.key]

	data = JSON.parse request.body.string
	table = db[params[:table].to_sym]

	data.each do |row|
		table << row
	end
end

delete '/sessions/:key' do
	session = Session.filter(:key => params[:key]).first
	stop 404 unless session

	if $connections[session.key]
		$connections[session.key].disconnect
		$connections.delete session.key
	end

	session.destroy

	"ok"
end

