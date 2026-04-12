require "../spec_helper"
require "../../src/vug/cache_manager"
require "file_utils"

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

describe Vug::MemoryCache do
  describe "#get with TTL" do
    it "returns value before TTL expires" do
      cache = Vug::MemoryCache.new(size_limit: 1024 * 1024, entry_ttl: 60.seconds)
      cache.set("url1", "/tmp/icon.png")
      cache.get("url1").should eq("/tmp/icon.png")
    end

    it "evicts expired entries on read" do
      cache = Vug::MemoryCache.new(size_limit: 1024 * 1024, entry_ttl: 1.millisecond)
      cache.set("url1", "/tmp/icon.png")
      sleep 5.milliseconds
      cache.get("url1").should be_nil
      cache.size.should eq(0)
    end

    it "cleans up current_size on expired eviction" do
      cache = Vug::MemoryCache.new(size_limit: 1024 * 1024, entry_ttl: 1.millisecond)
      cache.set("url1", "/tmp/icon.png")
      sleep 5.milliseconds
      cache.get("url1")
      # After eviction, adding a new entry shouldn't blow up
      cache.set("url2", "/tmp/icon2.png")
      cache.get("url2").should eq("/tmp/icon2.png")
    end

    it "removes expired entries from the insertion order queue" do
      cache = Vug::MemoryCache.new(size_limit: 128, entry_ttl: 1.millisecond)
      cache.set("url1", "/tmp/icon1.png")
      sleep 5.milliseconds
      cache.get("url1").should be_nil

      cache.set("url2", "/tmp/icon2.png")
      cache.get("url2").should eq("/tmp/icon2.png")
      cache.size.should eq(1)
    end
  end

  describe "#set with size limit" do
    it "evicts oldest entry when size limit exceeded" do
      # Create a tiny cache that fits only 2 entries
      dir = File.tempname("vug-cache-test")
      Dir.mkdir_p(dir)
      begin
        file1 = File.join(dir, "a.png")
        file2 = File.join(dir, "b.png")
        file3 = File.join(dir, "c.png")
        File.write(file1, "a" * 50)
        File.write(file2, "b" * 50)
        File.write(file3, "c" * 50)

        # Size limit: 100 bytes (fits ~2 entries of 50 bytes each)
        cache = Vug::MemoryCache.new(size_limit: 100, entry_ttl: 60.seconds)

        cache.set("url1", file1)
        cache.set("url2", file2)
        # Now set url3, which should evict url1 (oldest)
        cache.set("url3", file3)

        # url1 evicted, url2 and url3 present
        cache.get("url1").should be_nil
        cache.get("url2").should eq(file2)
        cache.get("url3").should eq(file3)
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "overwrites existing entry without leaking size" do
      dir = File.tempname("vug-cache-test")
      Dir.mkdir_p(dir)
      begin
        small = File.join(dir, "small.png")
        large = File.join(dir, "large.png")
        File.write(small, "a" * 10)
        File.write(large, "b" * 100)

        cache = Vug::MemoryCache.new(size_limit: 200, entry_ttl: 60.seconds)

        cache.set("url1", large)
        cache.set("url1", small) # overwrite with smaller
        cache.size.should eq(1)
        cache.get("url1").should eq(small)
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "rejects oversized entries before storing them" do
      dir = File.tempname("vug-cache-test")
      Dir.mkdir_p(dir)
      begin
        file = File.join(dir, "too-large.png")
        File.write(file, "x" * 128)

        cache = Vug::MemoryCache.new(size_limit: 64, entry_ttl: 60.seconds)
        cache.set("url1", file)

        cache.get("url1").should be_nil
        cache.size.should eq(0)
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  describe "#clear" do
    it "removes all entries and resets size" do
      cache = Vug::MemoryCache.new
      cache.set("url1", "/tmp/a.png")
      cache.set("url2", "/tmp/b.png")
      cache.size.should eq(2)

      cache.clear
      cache.size.should eq(0)
      cache.get("url1").should be_nil
      cache.get("url2").should be_nil
    end
  end

  describe "basic operations" do
    it "stores and retrieves values" do
      cache = Vug::MemoryCache.new
      cache.set("https://example.com/favicon.ico", "/favicons/abc123.png")
      cache.get("https://example.com/favicon.ico").should eq("/favicons/abc123.png")
    end

    it "returns nil for missing keys" do
      cache = Vug::MemoryCache.new
      cache.get("https://example.com/missing.ico").should be_nil
    end

    it "updates existing entry" do
      cache = Vug::MemoryCache.new
      cache.set("https://example.com/favicon.ico", "/favicons/old.png")
      cache.set("https://example.com/favicon.ico", "/favicons/new.png")
      cache.get("https://example.com/favicon.ico").should eq("/favicons/new.png")
    end

    it "tracks size" do
      cache = Vug::MemoryCache.new
      cache.size.should eq(0)
      cache.set("https://example.com/favicon.ico", "/favicons/abc.png")
      cache.size.should eq(1)
    end

    it "rejects non-absolute paths" do
      cache = Vug::MemoryCache.new
      cache.set("https://example.com/favicon.ico", "relative/path.png")
      cache.get("https://example.com/favicon.ico").should be_nil
    end

    it "keeps valid entries within TTL" do
      cache = Vug::MemoryCache.new(entry_ttl: 1.second)
      cache.set("https://example.com/favicon.ico", "/favicons/abc.png")
      cache.get("https://example.com/favicon.ico").should eq("/favicons/abc.png")
    end
  end

  describe "concurrent access" do
    it "handles concurrent access from multiple fibers without deadlock" do
      cache = Vug::MemoryCache.new
      results = Channel(String?).new(100)
      errors = Channel(Exception).new

      10.times do |i|
        spawn do
          begin
            url = "https://example#{i}.com/favicon.ico"
            path = "/favicons/#{i}.png"
            cache.set(url, path)
            result = cache.get(url)
            results.send(result)
          rescue e
            errors.send(e)
          end
        end
      end

      timeout = 5.seconds
      deadline = Time.monotonic + timeout
      completed = 0
      errors_received = [] of Exception

      while completed < 10 && Time.monotonic < deadline
        select
        when results.receive
          completed += 1
        when error = errors.receive
          errors_received << error
          completed += 1
        when timeout(100.milliseconds)
        end
      end

      errors_received.should be_empty
      completed.should eq(10)
    end

    it "handles concurrent gets and sets without deadlock" do
      cache = Vug::MemoryCache.new
      results = Channel(String?).new(50)
      errors = Channel(Exception).new

      5.times do |i|
        spawn do
          begin
            10.times do |j|
              url = "https://example#{i}.com/favicon#{j}.ico"
              cache.set(url, "/favicons/#{i}-#{j}.png")
            end
            results.send("set_done")
          rescue e
            errors.send(e)
          end
        end
      end

      5.times do |i|
        spawn do
          begin
            10.times do |j|
              url = "https://example#{i}.com/favicon#{j}.ico"
              cache.get(url)
            end
            results.send("get_done")
          rescue e
            errors.send(e)
          end
        end
      end

      timeout = 5.seconds
      deadline = Time.monotonic + timeout
      completed = 0
      errors_received = [] of Exception

      while completed < 10 && Time.monotonic < deadline
        select
        when results.receive
          completed += 1
        when error = errors.receive
          errors_received << error
          completed += 1
        when timeout(100.milliseconds)
        end
      end

      errors_received.should be_empty
      completed.should eq(10)
    end

    it "maintains consistency under concurrent set operations on same key" do
      cache = Vug::MemoryCache.new(size_limit: 1000)
      results = Channel(String).new(10)

      10.times do |i|
        spawn do
          cache.set("https://example.com/favicon.ico", "/favicons/#{i}.png")
          results.send("done")
        end
      end

      timeout = 5.seconds
      deadline = Time.monotonic + timeout
      completed = 0

      while completed < 10 && Time.monotonic < deadline
        select
        when results.receive
          completed += 1
        when timeout(100.milliseconds)
        end
      end

      completed.should eq(10)
      final_value = cache.get("https://example.com/favicon.ico")
      final_value.should_not be_nil
      final_value.as(String).should start_with("/favicons/")
    end
  end
end
