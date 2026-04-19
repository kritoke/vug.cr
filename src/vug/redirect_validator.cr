require "uri"
require "./redirect_handler_default"
require "./url_validator"
require "./config"

module Vug
  class RedirectValidator < RedirectHandler::Default
    def initialize(@config : Config)
      super(@config)
    end

    def validate_redirect_url(original_url : String, redirect_url : String) : Bool
      return false unless UrlValidator.valid_url?(original_url)
      return false unless UrlValidator.valid_url?(redirect_url)

      case decide(original_url, redirect_url, 0)
      when FetchAction::Follow
        true
      else
        false
      end
    end
  end
end
