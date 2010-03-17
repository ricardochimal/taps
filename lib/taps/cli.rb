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
		opts = clientoptparse(:pull)
		clientxfer(:pull, opts[:database_url], opts[:remote_url], opts[:chunksize])
	end

	def push
		opts = clientoptparse(:push)
		clientxfer(:push, opts[:database_url], opts[:remote_url], opts[:chunksize])
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
			:logging => true,
			:dump_errors => true,
		})
	end

	def version
		puts Taps.version
	end

	def help
		puts <<EOHELP
Options
=======
server    Start a taps database import/export server
pull      Pull a database from a taps server
push      Push a database to a taps server
version   Taps version

Add '-h' to any command to see their usage
EOHELP
	end

	def serveroptparse
		opts={:port => 5000, :database_url => nil, :login => nil, :password => nil, :debug => false}
		OptionParser.new do |o|
			o.banner = "Usage: #{File.basename($0)} server [OPTIONS] <local_database_url> <login> <password>"
			o.define_head "Start a taps database import/export server"

			o.on("-p", "--port=N", "Server Port") { |v| opts[:port] = v.to_i if v.to_i > 0 }
			o.on("-d", "--debug", "Enable Debug Messages") { |v| opts[:debug] = true }
			o.parse!(argv)

			opts[:database_url] = argv.shift
			opts[:login] = argv.shift
			opts[:password] = argv.shift

			if opts[:database_url].nil?
				$stderr.puts "Missing Database URL"
				puts o
				exit 1
			end
			if opts[:login].nil?
				$stderr.puts "Missing Login"
				puts o
				exit 1
			end
			if opts[:password].nil?
				$stderr.puts "Missing Password"
				puts o
				exit 1
			end
		end
		opts
	end

	def clientoptparse(cmd)
		opts={:chunksize => 1000, :database_url => nil, :remote_url => nil, :debug => false}
		OptionParser.new do |o|
			o.banner = "Usage: #{File.basename($0)} #{cmd} [OPTIONS] <local_database_url> <remote_url>"

			case cmd
			when :pull
				o.define_head "Pull a database from a taps server"
			when :push
				o.define_head "Push a database to a taps server"
			end

			o.on("-c", "--chunksize=N", "Initial Chunksize") { |v| opts[:chunksize] = (v.to_i < 10 ? 10 : v.to_i) }
			o.on("-d", "--debug", "Enable Debug Messages") { |v| opts[:debug] = true }
			o.parse!(argv)

			opts[:database_url] = argv.shift
			opts[:remote_url] = argv.shift

			if opts[:database_url].nil?
				$stderr.puts "Missing Database URL"
				puts o
				exit 1
			end
			if opts[:remote_url].nil?
				$stderr.puts "Missing Remote Taps URL"
				puts o
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
