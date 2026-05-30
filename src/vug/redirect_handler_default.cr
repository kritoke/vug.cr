require "uri"
require "./redirect_handler"
require "./config"

module Vug
  class RedirectHandler::Default < Vug::RedirectHandler
    def initialize(@config : Config)
      super(@config)
    end

    def decide(original : String, redirect_url : String, redirect_count : Int32) : Vug::FetchAction::Base
      # Enforce max redirects deterministically
      if redirect_count > @config.max_redirects
        return Vug::FetchAction::Deny.new("too_many_redirects")
      end

      # Basic loop detection: immediate cycle
      if original == redirect_url
        return Vug::FetchAction::Deny.new("redirect_loop")
      end

      # Parse URLs early to validate safely
      orig_uri = URI.parse(original)
      redir_uri = URI.parse(redirect_url)

      # Block HTTPS -> HTTP downgrades by default
      if orig_uri.scheme == "https" && redir_uri.scheme == "http"
        return Vug::FetchAction::Deny.new("scheme_downgrade")
      end

      # Prevent open redirect attacks: validate redirect target is same-origin.
      # Only allow redirects to the same host (domain + port) to prevent
      # redirection to external/untrusted domains controlled by attackers.
      orig_host = orig_uri.host || ""
      redir_host = redir_uri.host || ""

      # Normalize hosts: strip leading "www." for comparison to handle common cases
      # Allow redirect if either:
      # 1. Both www-stripped hosts match (www.example.com -> example.com)
      # 2. Both original hosts match (example.com -> example.com)
      orig_normalized = orig_host.sub(/^www\./, "")
      redir_normalized = redir_host.sub(/^www\./, "")

      same_origin = (orig_normalized == redir_normalized) || (orig_host == redir_host)
      unless same_origin
        return Vug::FetchAction::Deny.new("cross_domain_redirect")
      end

      # Port comparison: block redirects to different ports on the same host.
      # Default to standard ports (80 for http, 443 for https) when not specified.
      orig_port = orig_uri.port || (orig_uri.scheme == "https" ? 443 : 80)
      redir_port = redir_uri.port || (redir_uri.scheme == "https" ? 443 : 80)

      if orig_port != redir_port
        return Vug::FetchAction::Deny.new("port_mismatch")
      end

      # Block schemes other than http/https to prevent data: or javascript: URIs
      if redir_uri.scheme && !["http", "https"].includes?(redir_uri.scheme)
        return Vug::FetchAction::Deny.new("invalid_scheme")
      end

      Vug::FetchAction::Follow.new(redirect_url)
    rescue URI::Error
      Vug::FetchAction::Deny.new("invalid_url")
    end
  end
end
