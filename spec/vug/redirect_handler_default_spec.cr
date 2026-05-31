require "../spec_helper"
require "../../src/vug/redirect_handler_default"
require "../../src/vug/config"

describe Vug::RedirectHandler::Default do
  it "follows when under max redirects" do
    config = Vug::Config.new(max_redirects: 3)
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("https://example.com", "https://example.com/path", 1)
    res.is_a?(Vug::FetchAction::Follow).should be_true
  end

  it "denies cross-domain redirect" do
    config = Vug::Config.new
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("https://example.com", "https://other.com", 0)
    res.is_a?(Vug::FetchAction::Deny).should be_true
  end

  it "allows same host with www normalization" do
    config = Vug::Config.new
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("https://www.example.com", "https://example.com", 0)
    res.is_a?(Vug::FetchAction::Follow).should be_true
  end

  it "denies when redirect_count >= max_redirects" do
    config = Vug::Config.new(max_redirects: 2)
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("https://a", "https://b", 2)
    res.is_a?(Vug::FetchAction::Deny).should be_true
  end

  it "denies scheme downgrade" do
    config = Vug::Config.new
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("https://a", "http://b", 0)
    res.is_a?(Vug::FetchAction::Deny).should be_true
  end

  it "denies immediate loop" do
    config = Vug::Config.new
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("https://a", "https://a", 0)
    res.is_a?(Vug::FetchAction::Deny).should be_true
  end

  it "denies redirect to different port on same host" do
    config = Vug::Config.new
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("https://example.com", "https://example.com:8080", 0)
    res.is_a?(Vug::FetchAction::Deny).should be_true
    deny = res.as(Vug::FetchAction::Deny)
    deny.reason.should eq("port_mismatch")
  end

  it "allows redirect when both use default HTTPS port" do
    config = Vug::Config.new
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("https://example.com", "https://example.com:443/path", 0)
    res.is_a?(Vug::FetchAction::Follow).should be_true
  end

  it "allows redirect when both use default HTTP port" do
    config = Vug::Config.new
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("http://example.com", "http://example.com:80/path", 0)
    res.is_a?(Vug::FetchAction::Follow).should be_true
  end

  it "denies redirect from default port to non-standard port" do
    config = Vug::Config.new
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("http://example.com", "http://example.com:9090", 0)
    res.is_a?(Vug::FetchAction::Deny).should be_true
    deny = res.as(Vug::FetchAction::Deny)
    deny.reason.should eq("port_mismatch")
  end

  describe "trusted cross-domain redirects" do
    it "allows google.com -> gstatic.com redirect" do
      config = Vug::Config.new
      h = Vug::RedirectHandler::Default.new(config)
      res = h.decide(
        "https://www.google.com/s2/favicons?domain=example.com&sz=256",
        "https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://example.com&size=256",
        0
      )
      res.is_a?(Vug::FetchAction::Follow).should be_true
    end

    it "allows google.com (no www) -> gstatic.com redirect" do
      config = Vug::Config.new
      h = Vug::RedirectHandler::Default.new(config)
      res = h.decide(
        "https://google.com/s2/favicons?domain=example.com",
        "https://t2.gstatic.com/faviconV2?url=https://example.com",
        0
      )
      res.is_a?(Vug::FetchAction::Follow).should be_true
    end

    it "denies gstatic.com -> other.com redirect" do
      config = Vug::Config.new
      h = Vug::RedirectHandler::Default.new(config)
      res = h.decide(
        "https://t1.gstatic.com/faviconV2?url=example.com",
        "https://evil.com/steal",
        0
      )
      res.is_a?(Vug::FetchAction::Deny).should be_true
      deny = res.as(Vug::FetchAction::Deny)
      deny.reason.should eq("cross_domain_redirect")
    end

    it "denies untrusted cross-domain redirect" do
      config = Vug::Config.new
      h = Vug::RedirectHandler::Default.new(config)
      res = h.decide(
        "https://example.com/favicon.ico",
        "https://cdn.example.org/favicon.ico",
        0
      )
      res.is_a?(Vug::FetchAction::Deny).should be_true
      deny = res.as(Vug::FetchAction::Deny)
      deny.reason.should eq("cross_domain_redirect")
    end
  end
end
