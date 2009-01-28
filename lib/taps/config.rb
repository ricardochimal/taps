module Taps
class Config
	class << self
		attr_accessor :login, :password, :database_url, :remote_url
	end
end
end
