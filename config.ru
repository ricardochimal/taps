require 'rubygems'
require 'bundler/setup'
require 'extlib'

$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require 'taps/config'

Taps::Config.taps_database_url = ENV['TAPS_DATABASE_URL'] || ENV['DATABASE_URL']
Taps::Config.login = ENV['TAPS_LOGIN']
Taps::Config.password = ENV['TAPS_PASSWORD']

require 'taps/server'
run Taps::Server
