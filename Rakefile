require 'simplecov'

task :build do
  gemspec = Gem::Specification.load("taps.gemspec")
  target  = "pkg/#{gemspec.file_name}"

  FileUtils.mkdir_p File.dirname(target)
  Gem::Builder.new(gemspec).build
  FileUtils.mv gemspec.file_name, target
end

begin
  require 'rdoc/task'
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

desc "Run all specs; requires the bacon gem"
task :spec do
  SimpleCov.start if ENV["COVERAGE"]
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
