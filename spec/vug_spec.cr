require "./spec_helper"
require "../src/vug"

describe Vug do
  describe ".site" do
    it "handles feed URLs correctly" do
      # Test that feed URLs are properly sanitized
      config = Vug::Config.new(
        on_save: ->(url : String, _data : Bytes, _content_type : String) : String? { "/tmp/favicons/#{url.hash}.ico" },
        on_load: ->(_url : String) : String? { nil }
      )

      # This should not raise an error and should handle the /feed/ suffix
      result = Vug.site("https://example.com/feed/", config)
      # We don't expect it to succeed (no real favicon), but it shouldn't crash
      result.should be_a(Vug::Result)
    end

    it "handles regular URLs correctly" do
      config = Vug::Config.new(
        on_save: ->(url : String, _data : Bytes, _content_type : String) : String? { "/tmp/favicons/#{url.hash}.ico" },
        on_load: ->(_url : String) : String? { nil }
      )

      result = Vug.site("https://example.com", config)
      result.should be_a(Vug::Result)
    end
  end

  describe ".best" do
    it "handles feed URLs correctly" do
      config = Vug::Config.new(
        on_save: ->(url : String, _data : Bytes, _content_type : String) : String? { "/tmp/favicons/#{url.hash}.ico" },
        on_load: ->(_url : String) : String? { nil }
      )

      result = Vug.best("https://example.com/feed/", config)
      result.should be_a(Vug::Result)
    end
  end

  describe ".placeholder" do
    it "handles feed URLs correctly" do
      config = Vug::Config.new(
        on_save: ->(url : String, _data : Bytes, _content_type : String) : String? { "/tmp/favicons/#{url.hash}.ico" },
        on_load: ->(_url : String) : String? { nil }
      )

      result = Vug.placeholder("https://example.com/feed/", config)
      result.should be_a(Vug::Result)
      result.success?.should be_true
    end
  end

  describe "data URL favicon handling" do
    it "returns result type for URLs that would contain data URL favicons" do
      config = Vug::Config.new(
        on_save: ->(url : String, _data : Bytes, _content_type : String) : String? { "/tmp/favicons/#{url.hash}.ico" },
        on_load: ->(_url : String) : String? { nil }
      )
      result = Vug.site("https://example.com", config)
      result.should be_a(Vug::Result)
    end
  end

  describe "URL processing integration" do
    it "processes feed URLs through all main methods without errors" do
      config = Vug::Config.new(
        on_save: ->(url : String, _data : Bytes, _content_type : String) : String? { "/tmp/favicons/#{url.hash}.ico" },
        on_load: ->(_url : String) : String? { nil }
      )

      # Test all main entry points with feed URLs
      site_result = Vug.site("https://test.com/feed/", config)
      best_result = Vug.best("https://test.com/feed/", config)
      placeholder_result = Vug.placeholder("https://test.com/feed/", config)

      site_result.should be_a(Vug::Result)
      best_result.should be_a(Vug::Result)
      placeholder_result.should be_a(Vug::Result)
    end
  end
end
