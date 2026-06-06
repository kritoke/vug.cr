module Vug
  # Raised by the fetch loop when a URL has already been visited during
  # the same `Fetcher#fetch` call. Caught at the top of the loop and
  # converted to a `:too_many_redirects` failure result so callers see
  # a clean `Result` rather than an exception.
  class RedirectLoopError < Exception
    getter url : String

    def initialize(@url : String)
      super("Redirect loop detected: #{@url}")
    end
  end
end
