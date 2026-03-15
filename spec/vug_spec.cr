require "./spec_helper"
require "../src/vug"

describe Vug::ImageValidator do
  describe ".valid?" do
    it "identifies PNG images" do
      png_header = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]
      Vug::ImageValidator.valid?(png_header).should be_true
    end

    it "identifies JPEG images" do
      jpeg_header = Bytes[0xFF, 0xD8, 0xFF, 0x00, 0x00]
      Vug::ImageValidator.valid?(jpeg_header).should be_true
    end

    it "identifies ICO images" do
      ico_header = Bytes[0x00, 0x00, 0x01, 0x00, 0x00]
      Vug::ImageValidator.valid?(ico_header).should be_true
    end

    it "rejects invalid data" do
      invalid = Bytes[0x00, 0x00, 0x00, 0x00]
      Vug::ImageValidator.valid?(invalid).should be_false
    end

    it "rejects small data" do
      small = Bytes[0x00]
      Vug::ImageValidator.valid?(small).should be_false
    end
  end

  describe ".detect_content_type" do
    it "detects PNG" do
      png_header = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]
      Vug::ImageValidator.detect_content_type(png_header).should eq("image/png")
    end

    it "detects JPEG" do
      jpeg_header = Bytes[0xFF, 0xD8, 0xFF, 0x00, 0x00]
      Vug::ImageValidator.detect_content_type(jpeg_header).should eq("image/jpeg")
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
end
