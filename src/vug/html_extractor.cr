require "http/client"
require "uri"
require "./config"
require "./types"

module Vug
  class HtmlExtractor
    FAVICON_PATTERNS = [
      /<link[^>]+rel=["'](?:shortcut )?icon["'][^>]+href=["']([^"']+)["']/i,
      /<link[^>]+href=["']([^"']+)["'][^>]+rel=["'](?:shortcut )?icon["']/i,
      /<link[^>]+rel=["']apple-touch-icon["'][^>]+href=["']([^"']+)["']/i,
      /<link[^>]+rel=["']apple-touch-icon-precomposed["'][^>]+href=["']([^"']+)["']/i,
      /<link[^>]+type=["']image\/x-icon["'][^>]+href=["']([^"']+)["']/i,
      /<link[^>]+href=["']([^"']+\.ico)["'][^>]+rel=["']icon["']/i,
      /<link[^>]+rel=["']icon["'][^>]+type=["']image\/x-icon["'][^>]+href=["']([^"']+)["']/i,
    ]

    def initialize(@config : Config = Config.new)
    end

    def extract(site_url : String) : String?
      @config.debug("Extracting favicon from HTML: #{site_url}")

      begin
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
            html = response.body_io.gets_to_end
            @config.debug("HTML fetched: #{html.size} bytes")

            FAVICON_PATTERNS.each do |pattern|
              if match = html.match(pattern)
                favicon_url = match[1]
                favicon_url = normalize_url(favicon_url, clean_url)
                @config.debug("Found favicon in HTML: #{favicon_url}")
                return favicon_url
              end
            end

            @config.debug("No favicon link found in HTML")
          elsif response.status.not_found?
            @config.debug("HTML fetch 404: #{clean_url}")
          else
            @config.debug("HTML fetch error #{response.status_code}: #{clean_url}")
          end
        end
      rescue ex : Socket::Addrinfo::Error
        @config.debug("DNS lookup failed for: #{site_url}")
      rescue ex
        @config.error("extract(#{site_url})", ex)
        @config.debug("Error extracting favicon: #{ex.message}")
      end

      nil
    end

    private def normalize_url(favicon_url : String, base_url : String) : String
      if favicon_url.starts_with?("//")
        "https:#{favicon_url}"
      elsif !favicon_url.starts_with?("http")
        resolve_url(favicon_url, base_url)
      else
        favicon_url
      end
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
  end
end
