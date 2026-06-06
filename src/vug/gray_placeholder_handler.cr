require "uri"
require "./config"
require "./cache_coordinator"

module Vug
  # Detects gray/placeholder favicon images and generates fallback URLs.
  # Extracted from Fetcher to follow Single Responsibility Principle.
  class GrayPlaceholderHandler
    # DuckDuckGo's default icon returned when it has no real favicon
    # for a domain. This is a 32x32 PNG always at exactly 2441 bytes.
    DDG_DEFAULT_ICON_SIZE = 2441

    # Google favicon API returns a 198-byte SVG placeholder when no
    # real favicon exists for a domain.
    GOOGLE_PLACEHOLDER_SIZE = 198

    def initialize(@config : Config, @cache_coordinator : CacheCoordinator?)
    end

    # Returns true if the fetched data is a known gray placeholder image.
    def gray_placeholder?(url : String, data : Bytes?) : Bool
      return false if data.nil?
      return true if data.size == @config.gray_placeholder_size
      return true if ddg_default_icon?(url, data)
      false
    end

    # Try to find a cached larger version of a gray placeholder.
    # Returns the cached path if found, nil otherwise.
    def cached_larger_version(url : String) : String?
      return nil unless url.includes?("google.com/s2/favicons")
      larger_url = google_larger_url(url)
      @cache_coordinator.try(&.fetch(larger_url))
    end

    # Store a cached path under both the original and larger URL keys.
    def store_larger_version(url : String, cached_path : String) : Nil
      @cache_coordinator.try(&.store(url, cached_path))
    end

    # Generate a fallback URL for fetching a non-gray version of the favicon.
    def fallback_url(current_url : String) : String?
      if current_url.includes?("google.com/s2/favicons")
        google_larger_url(current_url)
      elsif current_url.includes?("icons.duckduckgo.com/ip3/")
        ddg_to_google_fallback(current_url)
      else
        generic_google_fallback(current_url)
      end
    end

    private def ddg_default_icon?(url : String, data : Bytes) : Bool
      url.includes?("icons.duckduckgo.com") && data.size == DDG_DEFAULT_ICON_SIZE
    end

    # Extract domain from DDG URL and build a Google favicon fallback URL.
    private def ddg_to_google_fallback(url : String) : String?
      if domain = extract_domain_from_ddg_url(url)
        encoded = URI.encode_www_form(domain)
        google_url = "https://www.google.com/s2/favicons?domain=#{encoded}&sz=256"
        @config.debug("DDG default icon, falling back to Google: #{google_url}")
        return google_url
      end
      @config.debug("DDG default icon but could not extract domain")
      nil
    end

    # Fall back to Google favicon API for any other gray placeholder source.
    private def generic_google_fallback(url : String) : String?
      @config.debug("Gray placeholder from non-Google source, trying Google fallback")
      if host = URI.parse(url).host
        encoded_host = URI.encode_www_form(host)
        google_url = "https://www.google.com/s2/favicons?domain=#{encoded_host}&sz=256"
        @config.debug("Google fallback URL: #{google_url}")
        return google_url
      end
      @config.debug("Gray placeholder fallback skipped: no valid host")
      nil
    rescue URI::Error
      @config.debug("Gray placeholder fallback skipped: URI parse failed")
      nil
    end

    private def extract_domain_from_ddg_url(url : String) : String?
      path = URI.parse(url).path
      return unless path
      match = path.match(%r{/ip3/(.+?)\.ico\z})
      match.try(&.[1])
    rescue URI::Error
      nil
    end

    private def google_larger_url(url : String) : String
      url.gsub(/sz=\d+/, "sz=256")
    end
  end
end
