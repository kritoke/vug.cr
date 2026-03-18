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
    def self.valid_scheme?(url : String) : Bool
      return false if url.starts_with?("javascript:")
      return false if url.starts_with?("vbscript:")
      return false if url.starts_with?("data:")
      return false if url.starts_with?("file:")
      return false if url.starts_with?("ftp:")
      true
    end
  end
end
