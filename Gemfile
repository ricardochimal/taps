source "http://rubygems.org"

# load the gem's dependencies
# gemspec

# manually load the gem's dependencies for now until
# bundler version on Heroku is upgraded
gem "rack"
gem "rest-client"
gem "sequel"
gem "sinatra"
gem "sqlite3-ruby"

group :development do
  gem "bacon"
  gem "mocha"
  gem "rack-test"
  gem "rake"
  gem "rcov"
end

# server-specific dependencies
group :server do
  gem "hoptoad_notifier"
  gem "extlib", "0.9.15"
  gem "mysql",  "2.8.1"
  gem "mysql2", "0.2.6"
  gem "pg",     "0.9.0"
  gem "thin",   "> 1.2.0"
end

