require 'optparse'
require 'tempfile'
require 'taps/config'

Taps::Config.taps_database_url = ENV['TAPS_DATABASE_URL'] || "sqlite://#{Tempfile.new('taps.db').path}"

module Taps
class Cli
	attr_accessor :argv

	def initialize(argv)
		@argv = argv
	end

	def run
		method = (argv.shift || 'help').to_sym
		if [:pull, :push, :server, :version].include? method
			send(method)
		else
			help
		end
	end

	def pull
		opts = clientoptparse
		clientxfer(:cmd_receive, opts[:database_url], opts[:remote_url], opts[:chunksize])
	end

	def push
		opts = clientoptparse
		clientxfer(:cmd_send, opts[:database_url], opts[:remote_url], opts[:chunksize])
	end

	def server
		opts = serveroptparse
		Taps::Config.database_url = opts[:database_url]
		Taps::Config.login = opts[:login]
		Taps::Config.password = opts[:password]

		Taps::Config.verify_database_url
		require 'taps/server'
		Taps::Server.run!({
			:port => opts[:port],
			:environment => :production,
			:logging => true
		})
	end

	def version
		puts Taps.version
	end

	def help
		puts <<EOHELP
Options
=======
server  <local_database_url> <login> <password> [--port=N]    Start a taps database import/export server
pull    <local_database_url> <remote_url> [--chunksize=N]     Pull a database from a taps server
push    <local_database_url> <remote_url> [--chunksize=N]     Push a database to a taps server
version                                                       Taps version
EOHELP
	end

	def serveroptparse
		opts={:port => 5000, :database_url => nil, :login => nil, :password => nil}
		OptionParser.new do |o|
			o.on("-p", "--port=N", "Port") { |v| opts[:port] = v.to_i if v.to_i > 0 }
			o.parse!(argv)

			opts[:database_url] = argv.shift
			opts[:login] = argv.shift
			opts[:password] = argv.shift

			if opts[:database_url].nil?
				$stderr.puts "Missing Database URL"
				help
				exit 1
			end
			if opts[:login].nil?
				$stderr.puts "Missing Login"
				help
				exit 1
			end
			if opts[:password].nil?
				$stderr.puts "Missing Password"
				help
				exit 1
			end
		end
		opts
	end

	def clientoptparse
		opts={:chunksize => 1000, :database_url => nil, :remote_url => nil}
		OptionParser.new do |o|
			o.on("-c", "--chunksize=N", "Chunksize") { |v| opts[:chunksize] = (v.to_i < 10 ? 10 : v.to_i) }
			o.parse!(argv)

			opts[:database_url] = argv.shift
			opts[:remote_url] = argv.shift

			if opts[:database_url].nil?
				$stderr.puts "Missing Database URL"
				help
				exit 1
			end
			if opts[:remote_url].nil?
				$stderr.puts "Missing Remote Taps URL"
				help
				exit 1
			end
		end

		opts
	end

	def clientxfer(method, database_url, remote_url, chunksize)
		Taps::Config.chunksize = chunksize
		Taps::Config.database_url = database_url
		Taps::Config.remote_url = remote_url

		Taps::Config.verify_database_url

		require 'taps/client_session'

		Taps::ClientSession.quickstart do |session|
			session.send(method)
		end
	end
end
end
