require 'thor'
require File.dirname(__FILE__) + '/config'

Taps::Config.taps_database_url = 'sqlite://taps.db'

module Taps
class Cli < Thor
	desc "server <local_database_url> <login> <password>", "Start a taps database import/export server"
	method_options(:port => :numeric)
	def server(database_url, login, password)
		Taps::Config.database_url = database_url
		Taps::Config.login = login
		Taps::Config.password = password

		port = options[:port] || 5000

		Taps::Config.verify_database_url

		require File.dirname(__FILE__) + '/server'
		Taps::Server.run!({
			:port => port,
			:environment => :production,
			:logging => true
		})
	end

	desc "pull <local_database_url> <remote_url>", "Pull a database from a taps server"
	method_options(:chunksize => :numeric)
	def receive(database_url, remote_url)
		clientxfer(:cmd_receive, database_url, remote_url)
	end

	desc "push <local_database_url> <remote_url>", "Push a database to a taps server"
	method_options(:chunksize => :numeric)
	def push(database_url, remote_url)
		clientxfer(:cmd_send, database_url, remote_url)
	end

	def clientxfer(method, database_url, remote_url)
		if options[:chunksize]
			Taps::Config.chunksize = options[:chunksize] < 100 ? 100 : options[:chunksize]
		else
			Taps::Config.chunksize = 1000
		end
		Taps::Config.database_url = database_url
		Taps::Config.remote_url = remote_url

		Taps::Config.verify_database_url

		require File.dirname(__FILE__) + '/client_session'

		Taps::ClientSession.quickstart do |session|
			session.send(method)
		end
	end
end
end
