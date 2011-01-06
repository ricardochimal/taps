require 'rubygems'
require 'extlib'

$:.unshift File.dirname(__FILE__) + '/lib'
require 'taps/config'

Taps::Config.taps_database_url = ENV['DATABASE_URL']
Taps::Config.login             = ENV["TAPS_LOGIN"]
Taps::Config.password          = ENV["TAPS_PASSWORD"]

require 'taps/server'
run Taps::Server
