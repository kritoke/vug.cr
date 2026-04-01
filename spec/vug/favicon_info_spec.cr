require "../spec_helper"
require "../../src/vug"

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
