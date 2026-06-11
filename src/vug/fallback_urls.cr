require "uri"
require "./url_processor"

module Vug
  # Shared fallback URL builders for favicon services.
  # Centralizes Google and DuckDuckGo URL construction to avoid duplication
  # across FaviconResolver and GrayPlaceholderHandler.
  module FallbackUrls
    GOOGLE_FAVICON_SIZE = 256

    def self.google_favicon_url(domain : String) : String
      host = UrlProcessor.extract_host_from_url(domain) || domain
      encoded_host = URI.encode_www_form(host)
      "https://www.google.com/s2/favicons?domain=#{encoded_host}&sz=#{GOOGLE_FAVICON_SIZE}"
    end

    def self.duckduckgo_favicon_url(domain : String) : String
      host = UrlProcessor.extract_host_from_url(domain) || domain
      encoded_host = URI.encode_path(host)
      "https://icons.duckduckgo.com/ip3/#{encoded_host}.ico"
    end
  end
end
