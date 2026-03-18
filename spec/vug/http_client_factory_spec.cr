require "../spec_helper"
require "../../src/vug/http_client_factory"

describe Vug::HttpClientFactory do
  describe "#create_client" do
    it "creates client with default config settings" do
      config = Vug::Config.new
      factory = Vug::HttpClientFactory.new(config)

      uri = URI.parse("https://example.com")
      client = factory.create_client(uri)

      # Verify client is created successfully
      client.should be_a(HTTP::Client)
    end

    it "creates client with custom config settings" do
      config = Vug::Config.new(timeout: 45.seconds, connect_timeout: 15.seconds)
      factory = Vug::HttpClientFactory.new(config)

      uri = URI.parse("https://example.com")
      client = factory.create_client(uri)

      # Verify client is created successfully
      client.should be_a(HTTP::Client)
    end

    it "creates HTTP client for HTTP URIs" do
      config = Vug::Config.new
      factory = Vug::HttpClientFactory.new(config)

      uri = URI.parse("http://example.com")
      client = factory.create_client(uri)

      client.host.should eq("example.com")
      client.port.should eq(80)
    end

    it "creates HTTPS client for HTTPS URIs" do
      config = Vug::Config.new
      factory = Vug::HttpClientFactory.new(config)

      uri = URI.parse("https://example.com")
      client = factory.create_client(uri)

      client.host.should eq("example.com")
      client.port.should eq(443)
    end
  end
end
