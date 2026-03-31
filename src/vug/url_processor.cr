require "uri"
require "./url_validator"

module Vug
  module UrlProcessor
    # Normalizes protocol-relative URLs (//example.com) to absolute URLs
    def self.normalize_url(url : String, base_scheme : String = "https") : String
      if url.starts_with?("//")
        "#{base_scheme}:#{url}"
      else
        url
      end
    end

    # Resolves relative URLs against a base URL
    def self.resolve_url(url : String, base : String) : String
      URI.parse(base).resolve(url.strip).to_s
    rescue
      url
    end

    # Validates that a URL has a safe scheme (http/https only)
    ALLOWED_SCHEMES = {"http", "https"}

    def self.valid_scheme?(url : String) : Bool
      scheme = url.split("://").first?.try(&.downcase)
      ALLOWED_SCHEMES.includes?(scheme)
    end

    # Extracts host from URL, handling feed URLs and HTTP/HTTPS schemes
    # Sanitizes by removing /feed/ suffix and extracts hostname from URI
    def self.extract_host_from_url(url : String) : String?
      sanitized = url.gsub(/\/feed\/?$/, "")

      if sanitized.starts_with?("http")
        begin
          parsed = URI.parse(sanitized)
          host = parsed.host
          host.nil? || host.empty? ? nil : host
        rescue
          nil
        end
      else
        sanitized.empty? ? nil : sanitized
      end
    end

    # Sanitizes URL by removing /feed/ suffix
    def self.sanitize_feed_url(url : String) : String
      url.gsub(/\/feed\/?$/, "")
    end
  end
end
