require "../spec_helper"
require "../../src/vug/cache_manager"

describe Vug::CacheManager do
  describe "#get" do
    it "returns from config-based storage when available" do
      config = Vug::Config.new(
        on_load: ->(url : String) : String? { url == "https://example.com/favicon.ico" ? "/favicons/example.png" : nil }
      )
      cache_manager = Vug::CacheManager.new(config)

      result = cache_manager.get("https://example.com/favicon.ico")
      result.should eq("/favicons/example.png")
    end

    it "falls back to memory cache when config storage misses" do
      config = Vug::Config.new(on_load: ->(_url : String) : String? { nil })
      memory_cache = Vug::MemoryCache.new
      memory_cache.set("https://example.com/favicon.ico", "/favicons/example.png")
      cache_manager = Vug::CacheManager.new(config, memory_cache)

      result = cache_manager.get("https://example.com/favicon.ico")
      result.should eq("/favicons/example.png")
    end

    it "returns nil when both storage types miss" do
      config = Vug::Config.new(on_load: ->(_url : String) : String? { nil })
      memory_cache = Vug::MemoryCache.new
      cache_manager = Vug::CacheManager.new(config, memory_cache)

      result = cache_manager.get("https://example.com/favicon.ico")
      result.should be_nil
    end

    it "works with no memory cache" do
      config = Vug::Config.new(
        on_load: ->(url : String) : String? { url == "https://example.com/favicon.ico" ? "/favicons/example.png" : nil }
      )
      cache_manager = Vug::CacheManager.new(config, nil)

      result = cache_manager.get("https://example.com/favicon.ico")
      result.should eq("/favicons/example.png")
    end
  end

  describe "#set" do
    it "stores in memory cache for absolute paths" do
      config = Vug::Config.new
      memory_cache = Vug::MemoryCache.new
      cache_manager = Vug::CacheManager.new(config, memory_cache)

      cache_manager.set("https://example.com/favicon.ico", "/favicons/example.png")
      result = memory_cache.get("https://example.com/favicon.ico")
      result.should eq("/favicons/example.png")
    end

    it "rejects relative paths" do
      config = Vug::Config.new
      memory_cache = Vug::MemoryCache.new
      cache_manager = Vug::CacheManager.new(config, memory_cache)

      cache_manager.set("https://example.com/favicon.ico", "relative/path.png")
      result = memory_cache.get("https://example.com/favicon.ico")
      result.should be_nil
    end

    it "works with no memory cache" do
      config = Vug::Config.new
      cache_manager = Vug::CacheManager.new(config, nil)

      # Should not raise an error
      cache_manager.set("https://example.com/favicon.ico", "/favicons/example.png")
    end
  end
end
