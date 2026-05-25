require "http/client"
require "./config"

module Vug
  # HTTP client factory.
  # Creates configured HTTP::Client instances for making requests.
  class HttpClientFactory
    def initialize(@config : Config)
    end

    # Create a new HTTP client configured with the current settings.
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

    # Release/close a client after use.
    # In Crystal, HTTP::Client handles connection pooling internally,
    # so we just close the client to ensure clean state.
    def release_client(uri : URI, client : HTTP::Client, success : Bool = true) : Nil
      # Always close the client to reset connection state.
      # The HTTP::Client's internal connection pool will handle reuse.
      client.close
    end
  end
end
