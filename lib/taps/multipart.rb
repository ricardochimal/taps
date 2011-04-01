require 'restclient'
require 'rack/utils'
require 'stringio'
require 'vendor/okjson'

module Taps
class Multipart
  class Container
    attr_accessor :attachments

    def initialize
      @attachments = []
    end

    def attach(opts)
      mp = Taps::Multipart.new(opts)
      attachments << mp
    end

    def generate
      hash = {}
      attachments.each do |mp|
        hash[mp.name] = mp
      end
      m = RestClient::Payload::Multipart.new(hash)
      [m.to_s, m.headers['Content-Type']]
    end
  end

  attr_reader :opts

  def initialize(opts={})
    @opts = opts
  end

  def name
    opts[:name]
  end

  def to_s
    opts[:payload]
  end

  def content_type
    opts[:content_type] || 'text/plain'
  end

  def original_filename
    opts[:original_filename]
  end

  def self.create
    c = Taps::Multipart::Container.new
    yield c
    c.generate
  end

  # response is a rest-client response
  def self.parse(response)
    content = response.to_s
    env = {
      'CONTENT_TYPE' => response.headers[:content_type],
      'CONTENT_LENGTH' => content.size,
      'rack.input' => StringIO.new(content)
    }

    params = Rack::Utils::Multipart.parse_multipart(env)
    params.symbolize_keys!
    params
  end

end
end
