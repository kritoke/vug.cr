require "../spec_helper"
require "../../src/vug/redirect_handler_default"
require "../../src/vug/config"

describe Vug::RedirectHandler::Default do
  it "follows when under max redirects" do
    config = Vug::Config.new(max_redirects: 3)
    h = Vug::RedirectHandler::Default.new(config)
    res = h.decide("https://a", "https://b", 1)
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
end
