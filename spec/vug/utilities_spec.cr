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