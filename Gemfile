source "http://rubygems.org"

# load the gem's dependencies
gemspec

# server-specific dependencies
group :server do
  gem "hoptoad_notifier"
  gem "extlib", "0.9.15"
  gem "mysql",  "2.8.1"
  gem "mysql2", "0.2.6"
  gem "sequel_pg", :require=>'sequel'
  gem "thin",   "> 1.2.0"
end

