require "time"

module Vug
  # Per-host rate limiter using a sliding window algorithm.
  # Tracks request timestamps per host and enforces a max requests per minute limit.
  class RateLimiter
    # Sliding window duration for rate limiting
    WINDOW = 1.minute

    # Default max requests per host per minute
    DEFAULT_MAX_PER_MINUTE = 60

    # Request record with timestamp for sliding window
    private record Request, timestamp : Time::Span

    def initialize(@max_per_minute : Int32 = DEFAULT_MAX_PER_MINUTE)
      @windows = {} of String => Array(Request)
      @mutex = Mutex.new
    end

    getter max_per_minute : Int32

    # Check if a request to the given host is allowed.
    # Returns true if under the limit, false if rate limited.
    def allow?(host : String) : Bool
      @mutex.synchronize do
        now = Time.monotonic
        cutoff = now - WINDOW

        # Get or initialize the host's request window
        requests = @windows[host] ||= [] of Request

        # Remove expired requests (outside the sliding window)
        requests.reject! { |req| req.timestamp < cutoff }

        # Check if we're under the limit
        if requests.size >= @max_per_minute
          return false
        end

        # Record this request
        requests << Request.new(now)
        true
      end
    end

    # Get remaining requests for a host in the current window.
    def remaining(host : String) : Int32
      @mutex.synchronize do
        now = Time.monotonic
        cutoff = now - WINDOW

        requests = @windows[host]?
        return @max_per_minute unless requests

        active = requests.count { |req| req.timestamp >= cutoff }
        (@max_per_minute - active).clamp(0, @max_per_minute)
      end
    end

    # Clear rate limit state for all hosts.
    def clear : Nil
      @mutex.synchronize { @windows.clear }
    end

    # Clear rate limit state for a specific host.
    def clear(host : String) : Nil
      @mutex.synchronize { @windows.delete(host) }
    end

    # Remove expired entries for hosts that haven't been queried recently.
    # Call periodically (e.g., from a background task) to prevent unbounded growth.
    # Note: Empty windows are automatically removed during each allow? call.
    # This method is for proactive cleanup when the limiter is not frequently used.
    def cleanup : Nil
      @mutex.synchronize do
        now = Time.monotonic
        cutoff = now - WINDOW

        # Remove expired requests from all windows
        @windows.each_value do |requests|
          requests.reject! { |req| req.timestamp < cutoff }
        end

        # Remove empty windows to prevent memory buildup
        @windows.reject! { |_, requests| requests.empty? }
      end
    end
  end
end
