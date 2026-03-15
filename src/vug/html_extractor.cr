require "http/client"
require "uri"
require "lexbor"
require "sanitize"
require "./config"
require "./types"

module Vug
  class HtmlExtractor
    FAVICON_SELECTORS = [
      "link[rel~='icon']",
      "link[rel~='shortcut']",
      "link[rel='apple-touch-icon']",
      "link[rel='apple-touch-icon-precomposed']",
      "link[type='image/x-icon']",
    ].freeze

    def initialize(@config : Config = Config.new)
    end

    def extract(site_url : String) : String?
      @config.debug("Extracting favicon from HTML: #{site_url}")

      begin
        return fetch_and_extract(site_url)
      rescue Socket::Addrinfo::Error
        @config.debug("DNS lookup failed for: #{site_url}")
      rescue ex
        @config.error("extract(#{site_url})", ex)
        @config.debug("Error extracting favicon: #{ex.message}")
      end

      nil
    end

    private def fetch_and_extract(site_url : String) : String
      clean_url = site_url.gsub(/\/feed\/?$/, "")
      @config.debug("Fetching HTML from: #{clean_url}")

      uri = URI.parse(clean_url)
      client = create_client(uri)

      headers = HTTP::Headers{
        "User-Agent" => @config.user_agent,
        "Accept"     => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      }

      client.get(uri.request_target, headers: headers) do |response|
        if response.status.success?
          memory = IO::Memory.new
          IO.copy(response.body_io, memory, limit: @config.max_size)
          html = memory.to_slice.to_s
          @config.debug("HTML fetched: #{html.size} bytes")

          html = sanitize_html(html)
          @config.debug("HTML sanitized: #{html.size} bytes")

          favicon_url = extract_favicon_url(html, clean_url)
          if favicon_url
            @config.debug("Found favicon in HTML: #{favicon_url}")
            return favicon_url
          end

          @config.debug("No favicon link found in HTML")
        elsif response.status.not_found?
          @config.debug("HTML fetch 404: #{clean_url}")
        else
          @config.debug("HTML fetch error #{response.status_code}: #{clean_url}")
        end
      end

      raise "No favicon found"
    end

    private def extract_favicon_url(html : String, base_url : String) : String?
      parser = Lexbor.new(html)

      FAVICON_SELECTORS.each do |selector|
        nodes = parser.css(selector)
        next if nodes.empty?

        nodes.each do |node|
          href = node["href"]?
          next if href.nil? || href.empty?

          normalized = normalize_url(href, base_url)
          return normalized if valid_scheme?(normalized)
        end
      end

      nil
    end

    private def normalize_url(favicon_url : String, base_url : String) : String
      if favicon_url.starts_with?("//")
        "https:#{favicon_url}"
      elsif !favicon_url.starts_with?("http")
        resolved = resolve_url(favicon_url.strip, base_url)
        return resolved if valid_scheme?(resolved)
        favicon_url
      else
        favicon_url
      end
    end

    private def valid_scheme?(url : String) : Bool
      return false if url.starts_with?("javascript:")
      return false if url.starts_with?("data:")
      return false if url.starts_with?("vbscript:")
      true
    end

    private def resolve_url(url : String, base : String) : String
      URI.parse(base).resolve(url.strip).to_s
    rescue
      url
    end

    private def create_client(uri : URI) : HTTP::Client
      client = HTTP::Client.new(uri)
      client.compress = true
      client.read_timeout = @config.timeout
      client.connect_timeout = @config.connect_timeout
      client
    end

    private def sanitize_html(html : String) : String
      Sanitize::Policy::HTMLSanitizer.common.process(html)
    rescue
      html
    end
  end
end
