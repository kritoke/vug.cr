require "uri"
require "./url_validator"
require "./config"

module Vug
  class RedirectValidator
    def initialize(@config : Config)
    end

    def validate_redirect_url(original_url : String, redirect_url : String) : Bool
      # Validate both original and redirect URLs
      return false unless UrlValidator.valid_url?(original_url)
      return false unless UrlValidator.valid_url?(redirect_url)

      # Additional check: ensure redirect doesn't change scheme in dangerous ways
      original_uri = URI.parse(original_url)
      redirect_uri = URI.parse(redirect_url)

      # Allow HTTPS -> HTTP redirects only if explicitly configured (not by default)
      # For now, be conservative and block scheme downgrades
      if original_uri.scheme == "https" && redirect_uri.scheme == "http"
        return false
      end

      true
    end
  end
end
