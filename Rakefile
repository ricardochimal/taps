begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "taps"
    s.summary = %Q{simple database import/export app}
    s.email = "ricardo@heroku.com"
    s.homepage = "http://github.com/ricardochimal/taps"
    s.description = "A simple database agnostic import/export app to transfer data to/from a remote database."
    s.authors = ["Ricardo Chimal, Jr.", "Adam Wiggins"]

    s.add_dependency 'sinatra', '~> 0.9.0'
    s.add_dependency 'activerecord', '= 2.2.2'
    s.add_dependency 'thor', '= 0.9.9'
    s.add_dependency 'rest-client', '~> 0.9.0'
    s.add_dependency 'sequel', '~> 2.10.0'

    s.rubyforge_project = "taps"
    s.rubygems_version = '1.3.1'

    s.files = FileList['spec/*.rb'] + FileList['lib/**/*.rb'] + ['README.rdoc', 'LICENSE', 'VERSION.yml', 'Rakefile']
    s.executables = ['taps', 'schema']
  end
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = 'taps'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |t|
    t.libs << 'spec'
    t.test_files = FileList['spec/*_spec.rb']
    t.verbose = true
  end
rescue LoadError
  puts "RCov is not available. In order to run rcov, you must: sudo gem install spicycode-rcov"
end

desc "Run all specs"
task :spec do
  system "bacon #{File.dirname(__FILE__)}/spec/*_spec.rb"
end

task :default => :spec
