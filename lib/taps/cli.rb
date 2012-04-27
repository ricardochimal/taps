require 'optparse'
require 'tempfile'
require 'taps/monkey'
require 'taps/config'
require 'taps/log'
require 'vendor/okjson'

Taps::Config.taps_database_url = ENV['TAPS_DATABASE_URL'] || begin
  # this is dirty but it solves a weird problem where the tempfile disappears mid-process
  require 'sqlite3'
  $__taps_database = Tempfile.new('taps.db')
  $__taps_database.open()
  "sqlite://#{$__taps_database.path}"
end

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
    Taps.log.level = Logger::DEBUG if opts[:debug]
    if opts[:resume_filename]
      clientresumexfer(:pull, opts)
    else
      clientxfer(:pull, opts)
    end
  end

  def push
    opts = clientoptparse(:push)
    Taps.log.level = Logger::DEBUG if opts[:debug]
    if opts[:resume_filename]
      clientresumexfer(:push, opts)
    else
      clientxfer(:push, opts)
    end
  end

  def server
    opts = serveroptparse
    Taps.log.level = Logger::DEBUG if opts[:debug]
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
    opts={:default_chunksize => 1000, :database_url => nil, :remote_url => nil, :debug => false, :resume_filename => nil, :disable_compresion => false, :indexes_first => false}
    OptionParser.new do |o|
      o.banner = "Usage: #{File.basename($0)} #{cmd} [OPTIONS] <local_database_url> <remote_url>"

      case cmd
      when :pull
        o.define_head "Pull a database from a taps server"
      when :push
        o.define_head "Push a database to a taps server"
      end

      o.on("-s", "--skip-schema", "Don't transfer the schema, just data") { |v| opts[:skip_schema] = true }
      o.on("-i", "--indexes-first", "Transfer indexes first before data") { |v| opts[:indexes_first] = true }
      o.on("-r", "--resume=file", "Resume a Taps Session from a stored file") { |v| opts[:resume_filename] = v }
      o.on("-c", "--chunksize=N", "Initial Chunksize") { |v| opts[:default_chunksize] = (v.to_i < 10 ? 10 : v.to_i) }
      o.on("-g", "--disable-compression", "Disable Compression") { |v| opts[:disable_compression] = true }
      o.on("-f", "--filter=regex", "Regex Filter for tables") { |v| opts[:table_filter] = v }
      o.on("-t", "--tables=A,B,C", Array, "Shortcut to filter on a list of tables") do |v|
        r_tables = v.collect { |t| "^#{t}$" }.join("|")
        opts[:table_filter] = "(#{r_tables})"
      end
      o.on("-e", "--exclude_tables=A,B,C", Array, "Shortcut to exclude a list of tables") { |v| opts[:exclude_tables] = v }
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

  def clientxfer(method, opts)
    database_url = opts.delete(:database_url)
    remote_url = opts.delete(:remote_url)

    Taps::Config.verify_database_url(database_url)

    require 'taps/operation'

    Taps::Operation.factory(method, database_url, remote_url, opts).run
  end

  def clientresumexfer(method, opts)
    session = OkJson.decode(File.read(opts.delete(:resume_filename)))
    session.symbolize_recursively!

    database_url = opts.delete(:database_url)
    remote_url = opts.delete(:remote_url) || session.delete(:remote_url)

    Taps::Config.verify_database_url(database_url)

    require 'taps/operation'

    newsession = session.merge({
      :default_chunksize => opts[:default_chunksize],
      :disable_compression => opts[:disable_compression],
      :resume => true,
    })

    Taps::Operation.factory(method, database_url, remote_url, newsession).run
  end

end
end
