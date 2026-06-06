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

    # Parse and validate a URL in one step: sanitize feed suffixes,
    # validate scheme and host safety, and return a parsed URI.
    # Returns nil if the URL is invalid, dangerous, or unparseable.
    def self.parse_and_validate(url : String) : URI?
      clean = sanitize_feed_url(url)
      return nil unless UrlValidator.valid_url?(clean)
      parsed = URI.parse(clean)
      return nil unless parsed.scheme
      parsed
    rescue URI::Error
      nil
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

    # Matches feed-like subdomains (e.g., feeds.example.com, feed.example.com)
    FEED_SUBDOMAIN_PATTERN = /\Afeeds?\./i

    # Returns true if the URL path looks like a feed endpoint
    def self.feed_url?(url : String) : Bool
      !!url.matches?(FEED_PATH_PATTERN)
    end

    # Returns true if the URL's host starts with a feed-like subdomain
    # (e.g., feeds.example.com or feed.example.com).
    def self.feed_subdomain?(url : String) : Bool
      host = extract_host_from_url(url)
      return false unless host
      !!host.matches?(FEED_SUBDOMAIN_PATTERN)
    end

    # Derives the site root URL from a feed URL.
    # For feed subdomains (e.g., feeds.example.com), strips the subdomain
    # and returns the parent domain origin.
    # For feed paths (e.g., example.com/atom.xml), strips the path and
    # returns the origin.
    # For non-feed URLs, returns the URL unchanged.
    def self.derive_site_url(url : String) : String
      begin
        uri = URI.parse(url)
        host = uri.host

        # Feed subdomain: strip feeds./feed. prefix to get parent domain
        if host && host.matches?(FEED_SUBDOMAIN_PATTERN)
          parent_host = host.sub(FEED_SUBDOMAIN_PATTERN, "")
          return "#{uri.scheme}://#{parent_host}"
        end

        return url unless feed_url?(url)
        "#{uri.scheme}://#{uri.host}"
      rescue URI::Error
        url
      end
    end
  end
end
