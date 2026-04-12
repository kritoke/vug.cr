require "../spec_helper"
require "../../src/vug/url_validator"

describe Vug::UrlValidator do
  describe ".valid_url?" do
    it "accepts valid HTTP URLs" do
      Vug::UrlValidator.valid_url?("http://example.com/favicon.ico").should be_true
    end

    it "accepts valid HTTPS URLs" do
      Vug::UrlValidator.valid_url?("https://example.com/favicon.ico").should be_true
    end

    it "accepts URLs with ports" do
      Vug::UrlValidator.valid_url?("https://example.com:8443/favicon.ico").should be_true
    end

    it "accepts URLs with paths" do
      Vug::UrlValidator.valid_url?("https://example.com/path/to/favicon.ico").should be_true
    end

    it "accepts URLs with query strings" do
      Vug::UrlValidator.valid_url?("https://example.com/favicon.ico?size=32").should be_true
    end

    it "rejects URLs without scheme" do
      Vug::UrlValidator.valid_url?("example.com/favicon.ico").should be_false
    end

    it "rejects invalid schemes" do
      Vug::UrlValidator.valid_url?("ftp://example.com/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("file:///etc/passwd").should be_false
    end

    it "rejects localhost URLs" do
      Vug::UrlValidator.valid_url?("http://localhost/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("http://localhost:3000/favicon.ico").should be_false
    end

    it "rejects private IP addresses" do
      Vug::UrlValidator.valid_url?("http://10.0.0.1/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("http://172.16.0.1/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("http://192.168.1.1/favicon.ico").should be_false
    end

    it "rejects .local domains" do
      Vug::UrlValidator.valid_url?("http://example.local/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("http://myserver.local/favicon.ico").should be_false
    end

    it "rejects 0.0.0.0" do
      Vug::UrlValidator.valid_url?("http://0.0.0.0/favicon.ico").should be_false
    end

    it "handles malformed URLs gracefully" do
      Vug::UrlValidator.valid_url?("not a url").should be_false
      Vug::UrlValidator.valid_url?("").should be_false
    end

    it "accepts public domains (DNS resolution check)" do
      Vug::UrlValidator.valid_url?("https://example.com/favicon.ico").should be_true
      Vug::UrlValidator.valid_url?("https://google.com/favicon.ico").should be_true
    end

    it "rejects trailing-dot localhost hostnames" do
      Vug::UrlValidator.valid_url?("http://localhost./favicon.ico").should be_false
    end

    it "recognizes IPv4-mapped IPv6 literal as loopback" do
      Vug::UrlValidator.valid_url?("http://[::ffff:127.0.0.1]/").should be_false
    end

    it "rejects carrier-grade NAT addresses (100.64.0.0/10)" do
      Vug::UrlValidator.valid_url?("http://100.64.0.1/").should be_false
    end
  end

  describe ".resolves_to_private_ip?" do
    it "returns false for public domains" do
      result = Vug::UrlValidator.resolves_to_private_ip?("example.com")
      result.should be_false
    end

    it "rejects domains that resolve to private IPs" do
      Vug::UrlValidator.resolves_to_private_ip?("localhost").should be_true
      Vug::UrlValidator.resolves_to_private_ip?("0.0.0.0").should be_true
    end

    it "returns true for empty DNS result for non-dot hosts (defense-in-depth)" do
      Vug::UrlValidator.resolves_to_private_ip?("nonexistent-ssrf-block-test").should be_true
    end
  end

  describe ".private_ip? (via host validation)" do
    it "detects IPv4 loopback through URL validation" do
      Vug::UrlValidator.valid_url?("http://127.0.0.1/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("http://127.0.0.2/favicon.ico").should be_false
    end

    it "detects 0.0.0.0 as private" do
      Vug::UrlValidator.valid_url?("http://0.0.0.0/favicon.ico").should be_false
    end

    it "detects RFC 1918 Class A (10.0.0.0/8)" do
      Vug::UrlValidator.valid_url?("http://10.0.0.1/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("http://10.255.255.255/favicon.ico").should be_false
    end

    it "detects RFC 1918 Class B (172.16.0.0/12)" do
      Vug::UrlValidator.valid_url?("http://172.16.0.1/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("http://172.31.255.255/favicon.ico").should be_false
    end

    it "allows non-private Class B addresses" do
      Vug::UrlValidator.valid_url?("http://172.15.0.1/favicon.ico").should be_true
      Vug::UrlValidator.valid_url?("http://172.32.0.1/favicon.ico").should be_true
    end

    it "detects RFC 1918 Class C (192.168.0.0/16)" do
      Vug::UrlValidator.valid_url?("http://192.168.0.1/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("http://192.168.255.255/favicon.ico").should be_false
    end

    it "allows public IP addresses" do
      Vug::UrlValidator.valid_url?("http://8.8.8.8/favicon.ico").should be_true
      Vug::UrlValidator.valid_url?("http://1.1.1.1/favicon.ico").should be_true
    end

    it "detects IPv6 loopback" do
      Vug::UrlValidator.valid_url?("http://[::1]/favicon.ico").should be_false
    end

    it "detects IPv6 unique local addresses" do
      Vug::UrlValidator.valid_url?("http://[fc00::1]/favicon.ico").should be_false
      Vug::UrlValidator.valid_url?("http://[fd00::1]/favicon.ico").should be_false
    end

    it "detects IPv6 link-local addresses" do
      Vug::UrlValidator.valid_url?("http://[fe80::1]/favicon.ico").should be_false
    end

    it "allows hostnames that happen to start with private IP prefixes" do
      Vug::UrlValidator.valid_url?("https://10thstreet.com/favicon.ico").should be_true
      Vug::UrlValidator.valid_url?("https://192168realty.com/favicon.ico").should be_true
      Vug::UrlValidator.valid_url?("https://172消防.com/favicon.ico").should be_true
    end
  end

  describe ".private_ip?" do
    it "returns false for hostnames" do
      Vug::UrlValidator.private_ip?("example.com").should be_false
      Vug::UrlValidator.private_ip?("10thstreet.com").should be_false
      Vug::UrlValidator.private_ip?("192168realty.com").should be_false
      Vug::UrlValidator.private_ip?("fcbayern.com").should be_false
    end

    it "returns true for IPv4 loopback" do
      Vug::UrlValidator.private_ip?("127.0.0.1").should be_true
      Vug::UrlValidator.private_ip?("127.0.0.2").should be_true
    end

    it "returns true for IPv4 private ranges" do
      Vug::UrlValidator.private_ip?("10.0.0.1").should be_true
      Vug::UrlValidator.private_ip?("172.16.0.1").should be_true
      Vug::UrlValidator.private_ip?("192.168.1.1").should be_true
    end

    it "returns true for IPv6 loopback" do
      Vug::UrlValidator.private_ip?("::1").should be_true
    end

    it "returns true for IPv6 unique local addresses" do
      Vug::UrlValidator.private_ip?("fc00::1").should be_true
      Vug::UrlValidator.private_ip?("fd00::1").should be_true
    end

    it "returns true for IPv6 link-local" do
      Vug::UrlValidator.private_ip?("fe80::1").should be_true
    end

    it "returns true for IPv4-mapped IPv6 addresses in private range" do
      Vug::UrlValidator.private_ip?("::ffff:192.168.1.1").should be_true
      Vug::UrlValidator.private_ip?("::ffff:10.0.0.1").should be_true
    end

    it "returns false for public IPs" do
      Vug::UrlValidator.private_ip?("8.8.8.8").should be_false
      Vug::UrlValidator.private_ip?("1.1.1.1").should be_false
      Vug::UrlValidator.private_ip?("2001:4860:4860::8888").should be_false
    end

    it "returns true for 0.0.0.0" do
      Vug::UrlValidator.private_ip?("0.0.0.0").should be_true
    end
  end
end
