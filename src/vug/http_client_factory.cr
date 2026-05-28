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
      create_client(uri, @config.timeout, @config.connect_timeout, @config.write_timeout)
    end

    # Create a new HTTP client with custom timeout settings.
    # Useful for requests that may need longer timeouts (e.g., slow servers).
    def create_client(
      uri : URI,
      read_timeout : Time::Span,
      connect_timeout : Time::Span? = nil,
      write_timeout : Time::Span? = nil
    ) : HTTP::Client
      HTTP::Client.new(uri).tap do |client|
        client.compress = true
        client.read_timeout = read_timeout > Time::Span.zero ? read_timeout : 30.seconds
        client.connect_timeout = (connect_timeout || @config.connect_timeout) > Time::Span.zero ? (connect_timeout || @config.connect_timeout) : 10.seconds
        client.write_timeout = (write_timeout || @config.write_timeout) > Time::Span.zero ? (write_timeout || @config.write_timeout) : 10.seconds
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
