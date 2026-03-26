require "../spec_helper"
require "../../src/vug"

describe Vug::DataUrlHandler do
  describe ".extract_from_url" do
    it "extracts valid base64 PNG data URL" do
      # Simple 1x1 transparent PNG in base64
      data_url = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAsgB/1KfFZIAAAAASUVORK5CYII="
      result = Vug::DataUrlHandler.extract_from_url(data_url)
      result.should_not be_nil
      if result
        data, media_type = result
        data.size.should be > 0
        media_type.should eq("image/png")
      end
    end

    it "returns nil for invalid data URL" do
      invalid_data_url = "data:image/png;base64,invalidbase64!"
      result = Vug::DataUrlHandler.extract_from_url(invalid_data_url)
      result.should be_nil
    end

    it "handles data URL without base64 marker" do
      simple_data_url = "data:text/plain,hello"
      result = Vug::DataUrlHandler.extract_from_url(simple_data_url)
      result.should be_nil
    end

    it "returns nil for non-image data URLs" do
      data_url = "data:text/plain;base64,SGVsbG8="
      result = Vug::DataUrlHandler.extract_from_url(data_url)
      result.should be_nil
    end
  end

  describe ".data_url?" do
    it "returns true for data URLs" do
      Vug::DataUrlHandler.data_url?("data:image/png;base64,foo").should be_true
    end

    it "returns false for regular URLs" do
      Vug::DataUrlHandler.data_url?("https://example.com/favicon.ico").should be_false
    end
  end
end

describe Vug::PlaceholderGenerator do
  describe ".generate_for_domain" do
    it "generates SVG for domain" do
      data, content_type = Vug::PlaceholderGenerator.generate_for_domain("example.com")
      data.size.should be > 0
      content_type.should eq("image/svg+xml")

      # Check that it contains expected elements
      svg_string = String.new(data)
      svg_string.should contain("<?xml")
      svg_string.should contain("<svg")
      svg_string.should contain("E") # First letter of example.com
    end

    it "handles www domains" do
      data, _ = Vug::PlaceholderGenerator.generate_for_domain("www.test.com")
      data.size.should be > 0
      svg_string = String.new(data)
      svg_string.should contain("T") # First letter of test.com (not www)
    end
  end

  describe ".generate_favicon_url" do
    it "generates data URL for domain" do
      url = Vug::PlaceholderGenerator.generate_favicon_url("example.com")
      url.should start_with("data:image/svg+xml;base64,")
    end
  end
end

describe Vug::MemoryCache do
  it "stores and retrieves values" do
    cache = Vug::MemoryCache.new
    cache.set("https://example.com/favicon.ico", "/favicons/abc123.png")
    cache.get("https://example.com/favicon.ico").should eq("/favicons/abc123.png")
  end

  it "returns nil for missing keys" do
    cache = Vug::MemoryCache.new
    cache.get("https://example.com/missing.ico").should be_nil
  end

  it "clears all entries" do
    cache = Vug::MemoryCache.new
    cache.set("https://example.com/favicon.ico", "/favicons/abc123.png")
    cache.clear
    cache.get("https://example.com/favicon.ico").should be_nil
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

  it "evicts oldest entry when size limit exceeded" do
    cache = Vug::MemoryCache.new(size_limit: 20)
    cache.set("https://a.com/favicon.ico", "/favicons/a.png")
    cache.set("https://b.com/favicon.ico", "/favicons/b.png")
    cache.set("https://c.com/favicon.ico", "/favicons/c.png")
    cache.get("https://a.com/favicon.ico").should be_nil
    cache.get("https://c.com/favicon.ico").should eq("/favicons/c.png")
  end

  it "respects TTL expiration" do
    cache = Vug::MemoryCache.new(entry_ttl: 1.millisecond)
    cache.set("https://example.com/favicon.ico", "/favicons/abc.png")
    sleep 2.milliseconds
    cache.get("https://example.com/favicon.ico").should be_nil
  end

  it "keeps valid entries within TTL" do
    cache = Vug::MemoryCache.new(entry_ttl: 1.second)
    cache.set("https://example.com/favicon.ico", "/favicons/abc.png")
    cache.get("https://example.com/favicon.ico").should eq("/favicons/abc.png")
  end

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

describe Vug::Config do
  it "has default values" do
    config = Vug::Config.new
    config.timeout.should eq(30.seconds)
    config.max_redirects.should eq(10)
    config.max_size.should eq(100 * 1024)
  end

  it "allows callback assignment" do
    config = Vug::Config.new
    debug_messages = [] of String
    config.on_debug = ->(msg : String) { debug_messages << msg }
    config.debug("test message")
    debug_messages.should eq(["test message"])
  end
end

describe Vug do
  describe ".google_favicon_url" do
    it "generates Google favicon URL for domain" do
      url = Vug.google_favicon_url("example.com")
      url.should eq("https://www.google.com/s2/favicons?domain=example.com&sz=256")
    end

    it "extracts host from full URL" do
      url = Vug.google_favicon_url("https://example.com/path")
      url.should eq("https://www.google.com/s2/favicons?domain=example.com&sz=256")
    end
  end

  describe ".duckduckgo_favicon_url" do
    it "generates DuckDuckGo favicon URL for domain" do
      url = Vug.duckduckgo_favicon_url("example.com")
      url.should eq("https://icons.duckduckgo.com/ip3/example.com.ico")
    end
  end
end

describe Vug::FaviconCollection do
  it "starts empty" do
    collection = Vug::FaviconCollection.new
    collection.empty?.should be_true
    collection.size.should eq(0)
  end

  it "adds and retrieves favicons" do
    collection = Vug::FaviconCollection.new
    favicon = Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/png", purpose: nil)
    collection.add(favicon)
    collection.size.should eq(1)
    collection.empty?.should be_false
  end

  it "returns best favicon by size priority" do
    collection = Vug::FaviconCollection.new
    collection.add(Vug::FaviconInfo.new(url: "https://example.com/small.png", sizes: "16x16", type: "image/png", purpose: nil))
    collection.add(Vug::FaviconInfo.new(url: "https://example.com/any.png", sizes: "any", type: "image/png", purpose: nil))
    collection.add(Vug::FaviconInfo.new(url: "https://example.com/large.png", sizes: "256x256", type: "image/png", purpose: nil))

    best = collection.best
    best.should_not be_nil
    best.as(Vug::FaviconInfo).sizes.should eq("any")
  end

  it "returns largest favicon by pixel area" do
    collection = Vug::FaviconCollection.new
    collection.add(Vug::FaviconInfo.new(url: "https://example.com/small.png", sizes: "16x16", type: "image/png", purpose: nil))
    collection.add(Vug::FaviconInfo.new(url: "https://example.com/large.png", sizes: "256x256", type: "image/png", purpose: nil))

    largest = collection.largest
    largest.should_not be_nil
    largest.as(Vug::FaviconInfo).url.should eq("https://example.com/large.png")
  end
end

describe Vug::FaviconInfo do
  describe "#size_pixels" do
    it "parses single size" do
      favicon = Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/png", purpose: nil)
      favicon.size_pixels.should eq(1024)
    end

    it "parses multiple sizes" do
      favicon = Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "16x16 32x32 48x48", type: "image/png", purpose: nil)
      favicon.size_pixels.should eq(2304)
    end

    it "returns nil for 'any' size" do
      favicon = Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "any", type: "image/png", purpose: nil)
      favicon.size_pixels.should be_nil
    end

    it "returns nil for nil sizes" do
      favicon = Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: nil, type: "image/png", purpose: nil)
      favicon.size_pixels.should be_nil
    end
  end

  describe "#has_any_size?" do
    it "returns true for 'any'" do
      favicon = Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "any", type: "image/png", purpose: nil)
      favicon.has_any_size?.should be_true
    end

    it "returns false for specific sizes" do
      favicon = Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/png", purpose: nil)
      favicon.has_any_size?.should be_false
    end
  end
end
