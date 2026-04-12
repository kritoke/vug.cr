module Vug
  abstract class RedirectHandler
    def initialize(@config : Config); end

    # Decide whether to follow a redirect. Return a FetchAction::Follow or FetchAction::Deny
    abstract def decide(original : String, redirect_url : String, redirect_count : Int32) : FetchAction::Base
  end
end
