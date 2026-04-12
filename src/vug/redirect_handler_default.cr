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
        if redirect_count >= @config.max_redirects
          return Vug::FetchAction::Deny.new("too_many_redirects")
        end

        # Basic loop detection: immediate cycle
        if original == redirect_url
          return Vug::FetchAction::Deny.new("redirect_loop")
        end

        # Block HTTPS -> HTTP downgrades by default
        begin
          orig = URI.parse(original)
          redir = URI.parse(redirect_url)
          if orig.scheme == "https" && redir.scheme == "http"
            return Vug::FetchAction::Deny.new("scheme_downgrade")
          end
        rescue e
          # If parsing fails, deny to be safe
          return Vug::FetchAction::Deny.new("invalid_url")
        end

        Vug::FetchAction::Follow.new(redirect_url)
      end
    end
end
