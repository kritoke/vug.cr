require "time"

module Vug
  # Per-host rate limiter using a sliding window algorithm.
  # Tracks request timestamps per host and enforces a max requests per minute limit.
  # Uses sorted arrays with binary search for O(log n) operations.
  class RateLimiter
    # Sliding window duration for rate limiting
    WINDOW = 1.minute

    # Default max requests per host per minute
    DEFAULT_MAX_PER_MINUTE = 60

    # Run cleanup after this many allow? calls to prevent unbounded growth
    CLEANUP_INTERVAL = 1000

    def initialize(@max_per_minute : Int32 = DEFAULT_MAX_PER_MINUTE)
      # Array of timestamps for each host, kept sorted for efficient pruning
      @windows = {} of String => Array(Time::Span)
      @mutex = Mutex.new
      @calls_since_cleanup = 0
    end

    getter max_per_minute : Int32

    # Check if a request to the given host is allowed.
    # Returns true if under the limit, false if rate limited.
    def allow?(host : String) : Bool
      @mutex.synchronize do
        now = Time.monotonic
        cutoff = now - WINDOW

        # Get or initialize the host's timestamps array
        timestamps = @windows[host] ||= [] of Time::Span

        # Binary search to find the first non-expired timestamp
        # This is O(log n) instead of O(n) for reject!
        idx = timestamps.bsearch_index { |ts| ts >= cutoff }
        if idx && idx > 0
          # Remove all expired entries (everything before idx)
          timestamps.shift(idx)
        elsif idx.nil?
          # All entries are expired
          timestamps.clear
        end

        # Check if we're under the limit
        if timestamps.size >= @max_per_minute
          return false
        end

        # Record this request
        timestamps << now
        @calls_since_cleanup += 1
        cleanup_if_needed
        true
      end
    end

    private def cleanup_if_needed : Nil
      if @calls_since_cleanup >= CLEANUP_INTERVAL
        @calls_since_cleanup = 0
        # Remove empty windows to prevent memory buildup
        @windows.reject! { |_, timestamps| timestamps.empty? }
      end
    end

    # Get remaining requests for a host in the current window.
    def remaining(host : String) : Int32
      @mutex.synchronize do
        now = Time.monotonic
        cutoff = now - WINDOW

        timestamps = @windows[host]?
        return @max_per_minute unless timestamps

        # Count active timestamps using binary search
        idx = timestamps.bsearch_index { |ts| ts >= cutoff } || timestamps.size
        active = timestamps.size - idx
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
    def cleanup : Nil
      @mutex.synchronize do
        now = Time.monotonic
        cutoff = now - WINDOW

        @windows.each_value do |timestamps|
          idx = timestamps.bsearch_index { |ts| ts >= cutoff } || timestamps.size
          timestamps.shift(idx) if idx > 0
        end

        # Remove empty windows to prevent memory buildup
        @windows.reject! { |_, timestamps| timestamps.empty? }
      end
    end
  end
end
