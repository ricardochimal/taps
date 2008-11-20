require 'rubygems'
require 'rest_client'
require 'sequel'
require 'json'

server = RestClient::Resource.new('http://localhost:4567')

uri = server['sessions'].post 'sqlite://full.db'
session = server[uri]

puts session['widgets'].get

session.delete

