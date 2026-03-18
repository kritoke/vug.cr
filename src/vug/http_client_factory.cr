require "http/client"
require "./config"

module Vug
  class HttpClientFactory
    def initialize(@config : Config)
    end

    def create_client(uri : URI) : HTTP::Client
      HTTP::Client.new(uri).tap do |client|
        client.compress = true
        client.read_timeout = @config.timeout
        client.connect_timeout = @config.connect_timeout
      end
    end
  end
end
