require "../spec_helper"
require "../../src/vug"

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
