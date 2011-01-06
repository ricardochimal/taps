begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "taps"
    s.summary = %Q{simple database import/export app}
    s.email = "ricardo@heroku.com"
    s.homepage = "http://github.com/ricardochimal/taps"
    s.description = "A simple database agnostic import/export app to transfer data to/from a remote database."
    s.authors = ["Ricardo Chimal, Jr."]

    s.rubygems_version = %q{1.3.5}

    s.add_dependency 'json', '~> 1.4.6'
    s.add_dependency 'sinatra', '~> 1.0.0'
    s.add_dependency 'rest-client', '>= 1.4.0', '< 1.7.0'
    s.add_dependency 'sequel', '~> 3.17.0'
    s.add_dependency 'sqlite3-ruby', '~> 1.2'
    s.add_dependency 'rack', '>= 1.0.1'

    s.rubyforge_project = "taps"

    s.files = FileList['spec/*.rb'] + FileList['lib/**/*.rb'] + ['README.rdoc', 'LICENSE', 'VERSION.yml', 'Rakefile'] + FileList['bin/*']
    s.executables = ['taps', 'schema']
  end
rescue LoadError => e
  if e.message =~ /jeweler/
    puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
  else
    puts e.message + ' -- while loading jeweler.'
  end
end

begin
  require 'rake/rdoctask'
  Rake::RDocTask.new do |rdoc|
    rdoc.rdoc_dir = 'rdoc'
    rdoc.title = 'taps'
    rdoc.options << '--line-numbers' << '--inline-source'
    rdoc.rdoc_files.include('README*')
    rdoc.rdoc_files.include('lib/**/*.rb')
  end
rescue LoadError
   puts "Rdoc is not available"
end

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |t|
    t.libs << 'spec'
    t.test_files = FileList['spec/*_spec.rb']
    t.verbose = true
  end
rescue LoadError
  puts "RCov is not available. In order to run rcov, you must: sudo gem install rcov"
end

desc "Run all specs; requires the bacon gem"
task :spec do
  if `which bacon`.empty?
    puts "bacon is not available. In order to run the specs, you must: sudo gem install bacon."
  else
    system "bacon #{File.dirname(__FILE__)}/spec/*_spec.rb"
  end
end

desc "copy/paste env vars for dev testing"
task :env do
  puts "export RUBYLIB='#{File.dirname(__FILE__) + '/lib'}'"
  puts "export RUBYOPT='-rrubygems'"
end

task :default => :spec
