source "http://rubygems.org"

# load the gem's dependencies
# gemspec

# manually load the gem's dependencies for now until
# bundler version on Heroku is upgraded
gem "rack",          ">= 1.0.1"
gem "rest-client",   ">= 1.4.0", "< 1.7.0"
gem "sequel",        "~> 3.20.0"
gem "sinatra",       "~> 1.0.0"
gem "sqlite3-ruby" , "~> 1.2"

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

