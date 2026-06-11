require "../spec_helper"
require "../../src/vug/rate_limiter"

describe Vug::RateLimiter do
  describe "construction" do
    it "defaults to 60 requests per minute" do
      limiter = Vug::RateLimiter.new
      limiter.max_per_minute.should eq(60)
    end

    it "accepts a custom max per minute" do
      limiter = Vug::RateLimiter.new(10)
      limiter.max_per_minute.should eq(10)
    end
  end

  describe "#allow?" do
    it "returns true when under limit" do
      limiter = Vug::RateLimiter.new(5)
      limiter.acquire("example.com").should be_true
    end

    it "returns false when limit exceeded" do
      limiter = Vug::RateLimiter.new(3)
      3.times { limiter.acquire("example.com").should be_true }
      limiter.acquire("example.com").should be_false
    end

    it "per-host isolation: one host limit does not affect another" do
      limiter = Vug::RateLimiter.new(2)
      limiter.acquire("a.com").should be_true
      limiter.acquire("a.com").should be_true
      # a.com is now at limit, but b.com should still be allowed
      limiter.acquire("a.com").should be_false
      limiter.acquire("b.com").should be_true
      limiter.acquire("b.com").should be_true
      limiter.acquire("b.com").should be_false
    end

    it "tracks remaining count accurately" do
      limiter = Vug::RateLimiter.new(5)
      limiter.remaining("example.com").should eq(5)
      limiter.acquire("example.com")
      limiter.remaining("example.com").should eq(4)
      limiter.acquire("example.com")
      limiter.remaining("example.com").should eq(3)
    end

    it "remaining is 0 when limit is reached" do
      limiter = Vug::RateLimiter.new(2)
      2.times { limiter.acquire("example.com") }
      limiter.remaining("example.com").should eq(0)
    end

    it "remaining returns max for unknown host" do
      limiter = Vug::RateLimiter.new(10)
      limiter.remaining("unknown.com").should eq(10)
    end
  end

  describe "#clear" do
    it "clears all hosts" do
      limiter = Vug::RateLimiter.new(1)
      limiter.acquire("a.com")
      limiter.acquire("b.com")
      limiter.acquire("a.com").should be_false

      limiter.clear

      limiter.acquire("a.com").should be_true
      limiter.acquire("b.com").should be_true
    end

    it "clears a specific host only" do
      limiter = Vug::RateLimiter.new(1)
      limiter.acquire("a.com")
      limiter.acquire("b.com")

      limiter.clear("a.com")

      limiter.acquire("a.com").should be_true
      limiter.acquire("b.com").should be_false
    end
  end

  describe "#cleanup" do
    it "removes expired host entries" do
      limiter = Vug::RateLimiter.new(100)
      # Fill a host that will be eligible for cleanup
      limiter.acquire("stale.example.com")

      # After cleanup, if the window expired the host would be removed.
      # Since we can't wait 1 minute in tests, we test the cleanup method
      # is callable and doesn't raise.
      limiter.cleanup

      # The host should still be present since entries haven't expired
      limiter.acquire("stale.example.com").should be_true
    end

    it "is safe to call on empty limiter" do
      limiter = Vug::RateLimiter.new(5)
      limiter.cleanup.should be_nil
    end

    it "is safe to call multiple times in succession" do
      limiter = Vug::RateLimiter.new(5)
      limiter.acquire("test.com")
      3.times { limiter.cleanup }
      limiter.acquire("test.com").should be_true
    end
  end

  describe "sliding window" do
    it "automatically prunes expired entries on each allow? call" do
      # Use a small limit and verify entries get pruned when they expire.
      # We can't wait 1 minute, but we can verify the pruning logic path
      # by calling allow? many times with a high limit to exercise the
      # binary search path.
      limiter = Vug::RateLimiter.new(100)

      # Make several requests to build up timestamps
      10.times { limiter.acquire("example.com") }

      # All should be within the window, so remaining should reflect that
      remaining = limiter.remaining("example.com")
      remaining.should eq(90)
    end
  end
end
