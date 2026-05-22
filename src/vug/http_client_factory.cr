require "http/client"
require "./config"

module Vug
  class HttpClientFactory
    def initialize(@config : Config)
    end

    def create_client(uri : URI) : HTTP::Client
      HTTP::Client.new(uri).tap do |client|
        client.compress = true
        # Ensure explicit timeout values to prevent Slowloris DoS attacks.
        # Fall back to sensible defaults if config values are unset or zero.
        client.read_timeout = @config.timeout > Time::Span.zero ? @config.timeout : 30.seconds
        client.connect_timeout = @config.connect_timeout > Time::Span.zero ? @config.connect_timeout : 10.seconds
        client.write_timeout = @config.write_timeout > Time::Span.zero ? @config.write_timeout : 10.seconds
      end
    end
  end
end
