require "uri"
require "./redirect_handler"
require "./config"

module Vug
  class RedirectHandler::Default < Vug::RedirectHandler
    # Known safe cross-domain redirect pairs for favicon services.
    # Maps a source host pattern to allowed redirect target host patterns.
    TRUSTED_REDIRECT_DOMAINS = {
      "google.com"     => ["gstatic.com"],
      "www.google.com" => ["gstatic.com"],
    }

    def initialize(@config : Config)
      super(@config)
    end

    def decide(original : String, redirect_url : String, redirect_count : Int32) : Vug::FetchAction::Base
      validate_redirect(original, redirect_url, redirect_count)
    rescue URI::Error
      Vug::FetchAction::Deny.new("invalid_url")
    end

    private def validate_redirect(original : String, redirect_url : String, redirect_count : Int32) : Vug::FetchAction::Base
      denial = check_limits(original, redirect_url, redirect_count)
      return denial if denial

      orig_uri = URI.parse(original)
      redir_uri = URI.parse(redirect_url)

      denial = check_scheme_and_origin(orig_uri, redir_uri)
      return denial if denial

      denial = check_port(orig_uri, redir_uri)
      return denial if denial

      Vug::FetchAction::Follow.new(redirect_url)
    end

    private def check_limits(original : String, redirect_url : String, redirect_count : Int32) : Vug::FetchAction::Deny?
      return Vug::FetchAction::Deny.new("too_many_redirects") if redirect_count > @config.max_redirects
      return Vug::FetchAction::Deny.new("redirect_loop") if original == redirect_url
      nil
    end

    private def check_scheme_and_origin(orig_uri : URI, redir_uri : URI) : Vug::FetchAction::Deny?
      if orig_uri.scheme == "https" && redir_uri.scheme == "http"
        return Vug::FetchAction::Deny.new("scheme_downgrade")
      end

      unless same_origin?(orig_uri, redir_uri) || trusted_redirect?(orig_uri.host || "", redir_uri.host || "")
        return Vug::FetchAction::Deny.new("cross_domain_redirect")
      end

      if redir_uri.scheme && !["http", "https"].includes?(redir_uri.scheme)
        return Vug::FetchAction::Deny.new("invalid_scheme")
      end

      nil
    end

    private def check_port(orig_uri : URI, redir_uri : URI) : Vug::FetchAction::Deny?
      orig_port = orig_uri.port || (orig_uri.scheme == "https" ? 443 : 80)
      redir_port = redir_uri.port || (redir_uri.scheme == "https" ? 443 : 80)

      return Vug::FetchAction::Deny.new("port_mismatch") if orig_port != redir_port
      nil
    end

    private def same_origin?(orig_uri : URI, redir_uri : URI) : Bool
      orig_host = orig_uri.host || ""
      redir_host = redir_uri.host || ""
      orig_normalized = orig_host.sub(/^www\./, "")
      redir_normalized = redir_host.sub(/^www\./, "")
      (orig_normalized == redir_normalized) || (orig_host == redir_host)
    end

    private def trusted_redirect?(orig_host : String, redir_host : String) : Bool
      TRUSTED_REDIRECT_DOMAINS.each do |source, targets|
        next unless host_matches?(orig_host, source)
        return true if targets.any? { |target| host_matches?(redir_host, target) }
      end
      false
    end

    # Matches exact host or any subdomain (e.g. "gstatic.com" matches "t1.gstatic.com")
    private def host_matches?(host : String, pattern : String) : Bool
      host == pattern || host.ends_with?(".#{pattern}")
    end
  end
end
