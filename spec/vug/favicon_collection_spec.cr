require "../spec_helper"
require "../../src/vug"

describe Vug::FaviconCollection do
  describe "LOGO_INDICATORS" do
    it "contains common logo-related terms" do
      Vug::FaviconCollection::LOGO_INDICATORS.should contain("logo")
      Vug::FaviconCollection::LOGO_INDICATORS.should contain("channel")
      Vug::FaviconCollection::LOGO_INDICATORS.should contain("brand")
      Vug::FaviconCollection::LOGO_INDICATORS.should contain("avatar")
    end
  end

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

  describe "logo filtering" do
    it "filters out URLs containing 'logo' in favor of regular favicon" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/images/logo.png", sizes: "128x128", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil))

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should contain("favicon.ico")
    end

    it "filters out URLs containing 'channel'" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/channels/avatar.jpg", sizes: "256x256", type: "image/jpeg", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil))

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should contain("favicon.ico")
    end

    it "filters out URLs containing 'brand'" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/brand/logo.png", sizes: "64x64", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/apple-touch-icon.png", sizes: "180x180", type: "image/png", purpose: nil))

      best = collection.best
      best.should_not be_nil
      # apple-touch-icon should be selected since brand/logo is filtered
      best.as(Vug::FaviconInfo).url.should contain("apple-touch-icon")
    end

    it "filters out URLs containing 'header'" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/header.png", sizes: "64x64", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "16x16", type: "image/x-icon", purpose: nil))

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should contain("favicon.ico")
    end

    it "filters out URLs containing 'banner'" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/banner.png", sizes: "200x100", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil))

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should contain("favicon.ico")
    end

    it "filters out URLs containing 'avatar'" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/user/avatar.png", sizes: "128x128", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil))

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should contain("favicon.ico")
    end

    it "filters out URLs containing 'profile'" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/profile/pic.png", sizes: "150x150", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil))

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should contain("favicon.ico")
    end

    it "filters out URLs containing 'artwork'" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/artwork.png", sizes: "300x300", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil))

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should contain("favicon.ico")
    end

    it "falls back to logo URL if no other options exist" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/images/logo.png", sizes: "128x128", type: "image/png", purpose: nil))

      best = collection.best
      best.should_not be_nil
      # Should return the logo since it's the only option
      best.as(Vug::FaviconInfo).url.should contain("logo.png")
    end

    it "is case-insensitive when filtering logos" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/LOGO.png", sizes: "64x64", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil))

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should contain("favicon.ico")
    end
  end

  describe "size-based priority" do
    it "deprioritizes images larger than 128x128" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/huge.png", sizes: "512x512", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/standard.png", sizes: "128x128", type: "image/png", purpose: nil))

      best = collection.best
      best.should_not be_nil
      # 128x128 should be preferred over 512x512 due to size deprioritization
      best.as(Vug::FaviconInfo).url.should contain("standard.png")
    end

    it "prefers larger size within normal range (<=128x128)" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/small.png", sizes: "32x32", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/medium.png", sizes: "128x128", type: "image/png", purpose: nil))

      best = collection.best
      best.should_not be_nil
      # Within normal range, larger is still preferred
      best.as(Vug::FaviconInfo).url.should contain("medium.png")
    end

    it "deprioritizes images just over 128x128 threshold" do
      collection = Vug::FaviconCollection.new
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/just_over.png", sizes: "130x130", type: "image/png", purpose: nil))
      collection.add(Vug::FaviconInfo.new(url: "https://example.com/just_under.png", sizes: "128x128", type: "image/png", purpose: nil))

      best = collection.best
      best.should_not be_nil
      # 128x128 should be preferred over 130x130
      best.as(Vug::FaviconInfo).url.should contain("just_under.png")
    end
  end

  describe "real-world HTML simulation" do
    it "selects favicon over channel logo from mixed HTML" do
      # Simulates a page like arstechnica.com that has both logos and favicons
      html_favicons = [
        Vug::FaviconInfo.new(url: "https://example.com/images/channel_logo.png", sizes: "256x256", type: "image/png", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/apple-touch-icon.png", sizes: "180x180", type: "image/png", purpose: nil),
      ]

      collection = Vug::FaviconCollection.new
      collection.add_all(html_favicons)

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should_not contain("channel_logo")
    end

    it "selects proper favicon when logos have larger dimensions" do
      html_favicons = [
        Vug::FaviconInfo.new(url: "https://example.com/brand_logo.png", sizes: "200x200", type: "image/png", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/sidebar_banner.png", sizes: "150x150", type: "image/png", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "48x48", type: "image/x-icon", purpose: nil),
      ]

      collection = Vug::FaviconCollection.new
      collection.add_all(html_favicons)

      best = collection.best
      best.should_not be_nil
      best.as(Vug::FaviconInfo).url.should contain("favicon.ico")
    end

    it "filters multiple logo variants and picks standard favicon" do
      html_favicons = [
        Vug::FaviconInfo.new(url: "https://example.com/logo.svg", sizes: "any", type: "image/svg+xml", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/header_logo.png", sizes: "64x64", type: "image/png", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/profile_pic.jpg", sizes: "128x128", type: "image/jpeg", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/favicon-16.png", sizes: "16x16", type: "image/png", purpose: nil),
      ]

      collection = Vug::FaviconCollection.new
      collection.add_all(html_favicons)

      best = collection.best
      best.should_not be_nil
      url = best.as(Vug::FaviconInfo).url
      url.should_not contain("logo")
      url.should_not contain("header")
      url.should_not contain("profile")
    end

    it "picks largest from deprioritized when all are logo-like or too large" do
      html_favicons = [
        Vug::FaviconInfo.new(url: "https://example.com/logo.png", sizes: "128x128", type: "image/png", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/huge.png", sizes: "256x256", type: "image/png", purpose: nil),
        Vug::FaviconInfo.new(url: "https://example.com/medium.png", sizes: "130x130", type: "image/png", purpose: nil),
      ]

      collection = Vug::FaviconCollection.new
      collection.add_all(html_favicons)

      best = collection.best
      best.should_not be_nil
      # logo.png is filtered (contains "logo"), so picks from deprioritized (>128x128)
      # Within deprioritized, larger pixels come first, so huge.png wins
      best.as(Vug::FaviconInfo).url.should contain("huge.png")
    end

    it "handles arstechnica-style page with channel avatars" do
      html_favicons = [
        Vug::FaviconInfo.new(url: "https://cdn.arstechnica.com/wp-content/uploads/2024/channels/default_logo-760x80.png", sizes: "760x80", type: "image/png", purpose: nil),
        Vug::FaviconInfo.new(url: "https://cdn.arstechnica.com/wp-content/uploads/2024/brand/ars-logo.png", sizes: "200x60", type: "image/png", purpose: nil),
        Vug::FaviconInfo.new(url: "https://arstechnica.com/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil),
        Vug::FaviconInfo.new(url: "https://arstechnica.com/apple-touch-icon.png", sizes: "180x180", type: "image/png", purpose: nil),
      ]

      collection = Vug::FaviconCollection.new
      collection.add_all(html_favicons)

      best = collection.best
      best.should_not be_nil
      url = best.as(Vug::FaviconInfo).url
      url.should_not contain("logo")
      url.should_not contain("brand")
      url.should_not contain("channels")
      url.should contain("favicon.ico")
    end

    it "handles YouTube-style channel icon mixed with favicons" do
      html_favicons = [
        Vug::FaviconInfo.new(url: "https://www.youtube.com/img/channels/UCxyz/channel_icon.jpg", sizes: "88x88", type: "image/jpeg", purpose: nil),
        Vug::FaviconInfo.new(url: "https://www.youtube.com/favicon.ico", sizes: "16x16", type: "image/x-icon", purpose: nil),
        Vug::FaviconInfo.new(url: "https://www.youtube.com/apple-touch-icon.png", sizes: "180x180", type: "image/png", purpose: nil),
      ]

      collection = Vug::FaviconCollection.new
      collection.add_all(html_favicons)

      best = collection.best
      best.should_not be_nil
      url = best.as(Vug::FaviconInfo).url
      url.should_not contain("channels")
      url.should_not contain("channel")
    end

    it "handles Twitch-style profile images" do
      html_favicons = [
        Vug::FaviconInfo.new(url: "https://static.twitchcdn.net/assets/images/logos/profile_image.png", sizes: "256x256", type: "image/png", purpose: nil),
        Vug::FaviconInfo.new(url: "https://www.twitch.tv/favicon.ico", sizes: "32x32", type: "image/x-icon", purpose: nil),
      ]

      collection = Vug::FaviconCollection.new
      collection.add_all(html_favicons)

      best = collection.best
      best.should_not be_nil
      url = best.as(Vug::FaviconInfo).url
      url.should_not contain("profile")
      url.should contain("favicon.ico")
    end
  end
end
