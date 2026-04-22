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
      resolved = if href.starts_with?("http")
                   normalize_url(href, base_scheme)
                 else
                   normalize_url(resolve_url(href.strip, base), base_scheme)
                 end

      return resolved if UrlValidator.valid_url?(resolved)
      ""
    end

    # Resolves relative URLs against a base URL
    def self.resolve_url(url : String, base : String) : String
      URI.parse(base).resolve(url.strip).to_s
    rescue URI::Error
      url
    end

    # Validates that a URL has a safe scheme (http/https only)
    def self.valid_scheme?(url : String) : Bool
      scheme = url.split("://").first?.try(&.downcase)
      UrlValidator.valid_scheme?(scheme)
    end

    # Extracts host from URL, handling feed URLs and HTTP/HTTPS schemes
    # Sanitizes by removing /feed/ suffix and extracts hostname from URI
    def self.extract_host_from_url(url : String) : String?
      sanitized = url.sub(/\/feed\/?\z/, "")

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
      url.sub(/\/feed\/?\z/, "")
    end

    # Matches common feed URL path suffixes
    FEED_PATH_PATTERN = %r{
      /(
        (atom|rss|feed|index)\.(xml|rss|rdf)
        | feeds?(/|\z)
        | (rss|atom|feed)(/|\z)
      )\z
    }xi

    # Returns true if the URL path looks like a feed endpoint
    def self.feed_url?(url : String) : Bool
      !!url.matches?(FEED_PATH_PATTERN)
    end

    # Derives the site root URL from a feed URL.
    # For feed URLs, strips the feed-specific path and returns the origin.
    # For non-feed URLs, returns the URL unchanged.
    def self.derive_site_url(url : String) : String
      return url unless feed_url?(url)
      begin
        uri = URI.parse(url)
        "#{uri.scheme}://#{uri.host}"
      rescue URI::Error
        url
      end
    end
  end
end
