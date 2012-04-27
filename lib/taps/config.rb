require 'sequel'
require 'taps/version'

Sequel.datetime_class = DateTime

module Taps
  def self.exiting=(val)
    @@exiting = val
  end

  def exiting?
    (@@exiting ||= false) == true
  end

  class Config
    class << self
      attr_accessor :taps_database_url
      attr_accessor :login, :password, :database_url, :remote_url
      attr_accessor :chunksize

      def verify_database_url(db_url=nil)
        db_url ||= self.database_url
        db = Sequel.connect(db_url)
        db.tables
        db.disconnect
      rescue Object => e
        puts "Failed to connect to database:\n  #{e.class} -> #{e}"
        exit 1
      end
    end
  end
end
