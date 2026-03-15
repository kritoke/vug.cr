require "../spec_helper"
require "../../src/vug"

describe Vug::Result do
  describe "#success?" do
    it "returns true for successful result" do
      result = Vug.success("https://example.com/favicon.ico", "/path/to/favicon.png")
      result.success?.should be_true
    end

    it "returns false for failure result" do
      result = Vug.failure("Not found", "https://example.com/favicon.ico")
      result.success?.should be_false
    end
  end

  describe "#failure?" do
    it "returns true for failure result" do
      result = Vug.failure("Not found", "https://example.com/favicon.ico")
      result.failure?.should be_true
    end

    it "returns false for successful result" do
      result = Vug.success("https://example.com/favicon.ico", "/path/to/favicon.png")
      result.failure?.should be_false
    end
  end

  describe "#redirect?" do
    it "returns true for redirect result" do
      result = Vug::Result.new(url: "https://example.com/new-favicon.ico", local_path: nil, content_type: nil, bytes: nil, error: nil)
      result.redirect?.should be_true
    end

    it "returns false for successful result" do
      result = Vug.success("https://example.com/favicon.ico", "/path/to/favicon.png")
      result.redirect?.should be_false
    end

    it "returns false for failure result" do
      result = Vug.failure("Error", "https://example.com/favicon.ico")
      result.redirect?.should be_false
    end
  end
end

describe "Result case statement type checking" do
  it "exercises all result predicates" do
    success = Vug.success("https://example.com/icon.png", "/path/icon.png")
    failure = Vug.failure("Error", "https://example.com/icon.png")
    redirect = Vug::Result.new(url: "https://example.com/new.png", local_path: nil, content_type: nil, bytes: nil, error: nil)

    success.success?.should be_true
    success.failure?.should be_false
    success.redirect?.should be_false

    failure.failure?.should be_true
    failure.success?.should be_false
    failure.redirect?.should be_false

    redirect.redirect?.should be_true
    redirect.success?.should be_false
    redirect.failure?.should be_false
  end
end

describe Vug::Fetcher do
  describe ".google_favicon_url" do
    it "generates Google favicon URL for domain" do
      url = Vug::Fetcher.google_favicon_url("example.com")
      url.should eq("https://www.google.com/s2/favicons?domain=example.com&sz=256")
    end

    it "extracts host from full URL" do
      url = Vug::Fetcher.google_favicon_url("https://example.com/path")
      url.should eq("https://www.google.com/s2/favicons?domain=example.com&sz=256")
    end
  end

  describe "#fetch" do
    it "handles failure for invalid URL" do
      saved_paths = {} of String => String
      config = Vug::Config.new(
        on_save: ->(url : String, data : Bytes, ct : String) { saved_paths[url] = "/saved"; "/saved".as(String?) }
      )
      fetcher = Vug::Fetcher.new(config)
      result = fetcher.fetch("not-a-valid-url")
      result.failure?.should be_true
    end
  end
end