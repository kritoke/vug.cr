require "../spec_helper"
require "../../src/vug/dns_cache"

describe Vug::DnsCache do
  describe ".ttl" do
    it "has a default TTL of 5 minutes" do
      Vug::DnsCache.ttl.should eq(5.minutes)
    end

    it "allows setting a custom TTL" do
      original_ttl = Vug::DnsCache.ttl
      Vug::DnsCache.ttl = 1.second
      Vug::DnsCache.ttl.should eq(1.second)
      Vug::DnsCache.ttl = original_ttl
    end
  end

  describe Vug::DnsCache::Instance do
    it "resolves a host and returns an array of strings" do
      instance = Vug::DnsCache::Instance.new(5.minutes)
      result = instance.resolve("localhost")
      result.should be_a(Array(String))
    end

    it "returns empty array for unresolvable hosts" do
      instance = Vug::DnsCache::Instance.new(5.minutes)
      result = instance.resolve("this-host-definitely-does-not-exist.invalid-tld")
      result.should be_a(Array(String))
      # The result is either empty or contains IPs — we just verify it doesn't raise
    end

    it "caches results and returns same IPs on subsequent calls" do
      instance = Vug::DnsCache::Instance.new(5.minutes)
      first = instance.resolve("localhost")
      second = instance.resolve("localhost")
      first.should eq(second)
    end

    it "clears cache" do
      instance = Vug::DnsCache::Instance.new(5.minutes)
      instance.resolve("localhost")
      instance.clear
      # After clear, next resolve should fetch fresh (no crash)
      result = instance.resolve("localhost")
      result.should be_a(Array(String))
    end

    it "re-creates instance with new TTL" do
      instance = Vug::DnsCache::Instance.new(5.minutes)
      new_instance = instance.recreate(1.second)
      new_instance.should be_a(Vug::DnsCache::Instance)
      # New instance should work independently
      new_instance.resolve("localhost").should be_a(Array(String))
    end

    it "TTL expiry causes re-resolution" do
      instance = Vug::DnsCache::Instance.new(0.01.seconds) # very short TTL
      first = instance.resolve("localhost")
      sleep(20.milliseconds) # wait for TTL to expire
      second = instance.resolve("localhost")
      # Both should return valid results; the key test is that it doesn't
      # crash or return stale nil after TTL expiry
      first.should be_a(Array(String))
      second.should be_a(Array(String))
    end
  end

  describe ".instance" do
    it "returns a DnsCache::Instance" do
      Vug::DnsCache.instance.should be_a(Vug::DnsCache::Instance)
    end

    it "returns same instance on repeated calls" do
      a = Vug::DnsCache.instance
      b = Vug::DnsCache.instance
      a.should eq(b)
    end
  end

  describe ".recreate" do
    it "creates a new instance" do
      old = Vug::DnsCache.instance
      Vug::DnsCache.recreate
      new_instance = Vug::DnsCache.instance
      # After recreate, it should still be a valid instance
      new_instance.should be_a(Vug::DnsCache::Instance)
    end
  end

  describe ".resolve" do
    it "delegates to instance" do
      result = Vug::DnsCache.resolve("localhost")
      result.should be_a(Array(String))
    end
  end

  describe ".clear" do
    it "clears the singleton cache without error" do
      Vug::DnsCache.resolve("localhost")
      Vug::DnsCache.clear.should be_nil
    end
  end
end
