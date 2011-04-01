require File.dirname(__FILE__) + '/base'

require 'taps/server'

require 'pp'

describe Taps::Server do
  def app
    Taps::Server.new
  end

  before do
    Taps::Config.login = 'taps'
    Taps::Config.password = 'tpass'

    @app = Taps::Server
    @auth_header = "Basic " + ["taps:tpass"].pack("m*")
  end

  it "asks for http basic authentication" do
    get '/'
    last_response.status.should == 401
  end

  it "verifies the client taps version" do
    get('/', { }, { 'HTTP_AUTHORIZATION' => @auth_header, 'HTTP_TAPS_VERSION' => Taps.version })
    last_response.status.should == 200
  end

  it "yells loudly if the client taps version doesn't match" do
    get('/', { }, { 'HTTP_AUTHORIZATION' => @auth_header, 'HTTP_TAPS_VERSION' => '0.0.1' })
    last_response.status.should == 417
  end
end

