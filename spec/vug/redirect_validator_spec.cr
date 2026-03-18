require "../spec_helper"
require "../../src/vug/redirect_validator"

describe Vug::RedirectValidator do
  describe "#validate_redirect_url" do
    it "allows HTTPS to HTTPS redirects" do
      config = Vug::Config.new
      validator = Vug::RedirectValidator.new(config)

      result = validator.validate_redirect_url(
        "https://example.com/favicon.ico",
        "https://cdn.example.com/favicon.ico"
      )
      result.should be_true
    end

    it "allows HTTP to HTTP redirects" do
      config = Vug::Config.new
      validator = Vug::RedirectValidator.new(config)

      result = validator.validate_redirect_url(
        "http://example.com/favicon.ico",
        "http://cdn.example.com/favicon.ico"
      )
      result.should be_true
    end

    it "allows HTTP to HTTPS redirects" do
      config = Vug::Config.new
      validator = Vug::RedirectValidator.new(config)

      result = validator.validate_redirect_url(
        "http://example.com/favicon.ico",
        "https://example.com/favicon.ico"
      )
      result.should be_true
    end

    it "blocks HTTPS to HTTP redirects (scheme downgrade)" do
      config = Vug::Config.new
      validator = Vug::RedirectValidator.new(config)

      result = validator.validate_redirect_url(
        "https://example.com/favicon.ico",
        "http://example.com/favicon.ico"
      )
      result.should be_false
    end

    it "blocks redirects to invalid URLs" do
      config = Vug::Config.new
      validator = Vug::RedirectValidator.new(config)

      result = validator.validate_redirect_url(
        "https://example.com/favicon.ico",
        "http://localhost/favicon.ico"
      )
      result.should be_false
    end

    it "blocks redirects from invalid URLs" do
      config = Vug::Config.new
      validator = Vug::RedirectValidator.new(config)

      result = validator.validate_redirect_url(
        "http://localhost/favicon.ico",
        "https://example.com/favicon.ico"
      )
      result.should be_false
    end

    it "blocks redirects to private IPs" do
      config = Vug::Config.new
      validator = Vug::RedirectValidator.new(config)

      result = validator.validate_redirect_url(
        "https://example.com/favicon.ico",
        "http://192.168.1.1/favicon.ico"
      )
      result.should be_false
    end
  end
end
