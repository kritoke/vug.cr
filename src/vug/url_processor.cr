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

    # Resolves relative URLs and normalizes protocol-relative URLs in one step.
    # If href is already absolute, it is normalized. If relative, it is resolved
    # against base first, then normalized.
    def self.resolve_and_normalize(href : String, base : String, base_scheme : String = "https") : String
      if href.starts_with?("http")
        normalize_url(href, base_scheme)
      else
        resolved = resolve_url(href.strip, base)
        normalize_url(resolved, base_scheme)
      end
    end

    # Resolves relative URLs against a base URL
    def self.resolve_url(url : String, base : String) : String
      URI.parse(base).resolve(url.strip).to_s
    rescue URI::Error
      url
    end

    # Validates that a URL has a safe scheme (http/https only)
    ALLOWED_SCHEMES = {"http", "https"}

    def self.valid_scheme?(url : String) : Bool
      scheme = url.split("://").first?.try(&.downcase)
      ALLOWED_SCHEMES.includes?(scheme)
    rescue URI::Error
      false
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
        rescue URI::Error
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
