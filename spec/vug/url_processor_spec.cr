require "../spec_helper"
require "../../src/vug/url_processor"

describe Vug::UrlProcessor do
  describe ".normalize_url" do
    it "converts protocol-relative URLs to HTTPS" do
      result = Vug::UrlProcessor.normalize_url("//example.com/favicon.ico")
      result.should eq("https://example.com/favicon.ico")
    end

    it "converts protocol-relative URLs to HTTP with custom scheme" do
      result = Vug::UrlProcessor.normalize_url("//example.com/favicon.ico", "http")
      result.should eq("http://example.com/favicon.ico")
    end

    it "leaves absolute URLs unchanged" do
      result = Vug::UrlProcessor.normalize_url("https://example.com/favicon.ico")
      result.should eq("https://example.com/favicon.ico")
    end

    it "leaves relative URLs unchanged" do
      result = Vug::UrlProcessor.normalize_url("/favicon.ico")
      result.should eq("/favicon.ico")
    end
  end

  describe ".resolve_url" do
    it "resolves relative path against base URL" do
      result = Vug::UrlProcessor.resolve_url("/favicon.ico", "https://example.com/page.html")
      result.should eq("https://example.com/favicon.ico")
    end

    it "resolves complex relative path" do
      result = Vug::UrlProcessor.resolve_url("../images/favicon.png", "https://example.com/docs/page.html")
      result.should eq("https://example.com/images/favicon.png")
    end
  end

  describe ".valid_scheme?" do
    it "allows HTTP URLs" do
      Vug::UrlProcessor.valid_scheme?("http://example.com/favicon.ico").should be_true
    end

    it "allows HTTPS URLs" do
      Vug::UrlProcessor.valid_scheme?("https://example.com/favicon.ico").should be_true
    end

    it "allows uppercase HTTP scheme" do
      Vug::UrlProcessor.valid_scheme?("HTTP://example.com/favicon.ico").should be_true
    end

    it "allows mixed case HTTPS scheme" do
      Vug::UrlProcessor.valid_scheme?("HtTpS://example.com/favicon.ico").should be_true
    end

    it "rejects javascript URLs" do
      Vug::UrlProcessor.valid_scheme?("javascript:alert(1)").should be_false
    end

    it "rejects vbscript URLs" do
      Vug::UrlProcessor.valid_scheme?("vbscript:alert(1)").should be_false
    end

    it "rejects data URLs" do
      Vug::UrlProcessor.valid_scheme?("data:text/html,<script>").should be_false
    end

    it "rejects file URLs" do
      Vug::UrlProcessor.valid_scheme?("file:///etc/passwd").should be_false
    end

    it "rejects ftp URLs" do
      Vug::UrlProcessor.valid_scheme?("ftp://example.com/file.txt").should be_false
    end

    it "rejects gopher URLs" do
      Vug::UrlProcessor.valid_scheme?("gopher://example.com/").should be_false
    end

    it "rejects unknown schemes" do
      Vug::UrlProcessor.valid_scheme?("custom://example.com/").should be_false
    end
  end

  describe ".extract_host_from_url" do
    it "extracts host from HTTP URL" do
      result = Vug::UrlProcessor.extract_host_from_url("http://example.com/path")
      result.should eq("example.com")
    end

    it "extracts host from HTTPS URL" do
      result = Vug::UrlProcessor.extract_host_from_url("https://example.com/path")
      result.should eq("example.com")
    end

    it "handles feed URLs" do
      result = Vug::UrlProcessor.extract_host_from_url("https://example.com/feed/")
      result.should eq("example.com")
    end

    it "handles feed URLs without trailing slash" do
      result = Vug::UrlProcessor.extract_host_from_url("https://example.com/feed")
      result.should eq("example.com")
    end

    it "returns domain as-is for non-HTTP URLs" do
      result = Vug::UrlProcessor.extract_host_from_url("example.com")
      result.should eq("example.com")
    end

    it "returns nil for invalid HTTP URLs" do
      result = Vug::UrlProcessor.extract_host_from_url("http://")
      result.should be_nil
    end

    it "returns nil for empty strings" do
      result = Vug::UrlProcessor.extract_host_from_url("")
      result.should be_nil
    end
  end

  describe ".sanitize_feed_url" do
    it "removes /feed/ suffix" do
      result = Vug::UrlProcessor.sanitize_feed_url("https://example.com/feed/")
      result.should eq("https://example.com")
    end

    it "removes /feed suffix without trailing slash" do
      result = Vug::UrlProcessor.sanitize_feed_url("https://example.com/feed")
      result.should eq("https://example.com")
    end

    it "leaves non-feed URLs unchanged" do
      result = Vug::UrlProcessor.sanitize_feed_url("https://example.com/path")
      result.should eq("https://example.com/path")
    end

    it "handles multiple feed patterns" do
      result = Vug::UrlProcessor.sanitize_feed_url("https://example.com/feed/feed/")
      result.should eq("https://example.com/feed")
    end
  end
end
