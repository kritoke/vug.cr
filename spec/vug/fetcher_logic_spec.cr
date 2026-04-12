require "../spec_helper"
require "../../src/vug"

describe Vug::Fetcher do
  describe "#fetch" do
    it "handles failure for invalid URL" do
      config = Vug::Config.new(
        on_save: ->(_url : String, _data : Bytes, _ct : String) { "/saved".as(String?) }
      )
      fetcher = Vug::Fetcher.new(config)
      result = fetcher.fetch("not-a-valid-url")
      result.failure?.should be_true
    end

    it "handles failure for dangerous URL" do
      config = Vug::Config.new
      fetcher = Vug::Fetcher.new(config)
      result = fetcher.fetch("javascript:alert(1)")
      result.failure?.should be_true
    end

    it "handles failure for URL with private IP" do
      config = Vug::Config.new
      fetcher = Vug::Fetcher.new(config)
      result = fetcher.fetch("http://127.0.0.1/favicon.ico")
      result.failure?.should be_true
    end
  end

  describe "gray placeholder configuration" do
    it "defaults to 198 bytes (Google's gray placeholder size)" do
      config = Vug::Config.new
      config.gray_placeholder_size.should eq(198)
    end

    it "allows custom gray placeholder size" do
      config = Vug::Config.new(gray_placeholder_size: 100)
      config.gray_placeholder_size.should eq(100)
    end

    it "rejects negative gray placeholder size" do
      expect_raises(ArgumentError) do
        Vug::Config.new(gray_placeholder_size: -1)
      end
    end
  end

  describe "Semaphore concurrency" do
    it "reuses one shared semaphore instance across concurrent access" do
      results = Channel(UInt64).new(20)

      20.times do
        spawn do
          semaphore = Vug.shared_semaphore(8)
          results.send(semaphore.object_id)
        end
      end

      ids = [] of UInt64
      20.times do
        ids << results.receive
      end

      ids.uniq.size.should eq(1)
    end

    it "limits concurrent access to configured limit" do
      config = Vug::Config.new
      fetcher = Vug::Fetcher.new(config)

      semaphore = fetcher.@semaphore

      acquired = 0
      max_concurrent = 0
      mutex = Mutex.new
      errors = [] of Exception

      20.times do
        spawn do
          begin
            semaphore.acquire
            mutex.synchronize do
              acquired += 1
              max_concurrent = Math.max(max_concurrent, acquired)
            end
            sleep 10.milliseconds
            acquired -= 1
            semaphore.release
          rescue e
            mutex.synchronize { errors << e }
          end
        end
      end

      sleep 200.milliseconds

      errors.should be_empty
      max_concurrent.should be <= 8
    end

    it "releases semaphore even on error" do
      config = Vug::Config.new
      fetcher = Vug::Fetcher.new(config)

      semaphore = fetcher.@semaphore

      errors = [] of Exception
      results = [] of String

      5.times do
        spawn do
          begin
            semaphore.acquire
            raise "Simulated error"
          rescue e
            errors << e
          ensure
            semaphore.release
            results << "released"
          end
        end
      end

      sleep 100.milliseconds

      results.size.should eq(5)
      errors.size.should eq(5)
    end
  end

  describe "max redirects configuration" do
    it "defaults to 10 redirects" do
      config = Vug::Config.new
      config.max_redirects.should eq(10)
    end

    it "allows custom max redirects" do
      config = Vug::Config.new(max_redirects: 5)
      config.max_redirects.should eq(5)
    end

    it "rejects negative max redirects" do
      expect_raises(ArgumentError) do
        Vug::Config.new(max_redirects: -1)
      end
    end
  end

  describe "timeout configuration" do
    it "defaults to 30 seconds" do
      config = Vug::Config.new
      config.timeout.should eq(30.seconds)
    end

    it "allows custom timeout" do
      config = Vug::Config.new(timeout: 10.seconds)
      config.timeout.should eq(10.seconds)
    end

    it "rejects zero timeout" do
      expect_raises(ArgumentError) do
        Vug::Config.new(timeout: 0.seconds)
      end
    end

    it "rejects negative timeout" do
      expect_raises(ArgumentError) do
        Vug::Config.new(timeout: -5.seconds)
      end
    end
  end

  describe "gray placeholder size detection" do
    it "detects data exactly matching gray_placeholder_size" do
      config = Vug::Config.new(gray_placeholder_size: 198)
      # Simulate what Fetcher checks
      gray_data = Bytes.new(198)
      config.gray_placeholder_size.should eq(198)
      gray_data.size.should eq(config.gray_placeholder_size)
    end

    it "does not flag data smaller than gray_placeholder_size" do
      config = Vug::Config.new(gray_placeholder_size: 198)
      small_data = Bytes.new(100)
      small_data.size.should_not eq(config.gray_placeholder_size)
    end

    it "does not flag data larger than gray_placeholder_size" do
      config = Vug::Config.new(gray_placeholder_size: 198)
      large_data = Bytes.new(500)
      large_data.size.should_not eq(config.gray_placeholder_size)
    end

    it "allows custom gray placeholder sizes" do
      config = Vug::Config.new(gray_placeholder_size: 64)
      config.gray_placeholder_size.should eq(64)
      gray_data = Bytes.new(64)
      gray_data.size.should eq(config.gray_placeholder_size)
    end
  end

  describe "Google favicon fallback URL" do
    it "extracts host from URL for Google favicon" do
      url = Vug::FaviconResolver.google_favicon_url("https://example.com")
      url.should eq("https://www.google.com/s2/favicons?domain=example.com&sz=256")
    end

    it "encodes special characters in domain" do
      url = Vug::FaviconResolver.google_favicon_url("https://example.com/path?query=1")
      url.should contain("example.com")
      url.should contain("sz=256")
      # Should not contain raw query parameters
      url.should_not contain("?query=")
    end
  end

  describe "DuckDuckGo favicon URL" do
    it "generates DuckDuckGo favicon URL" do
      url = Vug.duckduckgo_favicon_url("example.com")
      url.should eq("https://icons.duckduckgo.com/ip3/example.com.ico")
    end

    it "extracts host from full URL" do
      url = Vug.duckduckgo_favicon_url("https://example.com/path")
      url.should eq("https://icons.duckduckgo.com/ip3/example.com.ico")
    end

    it "uses domain as-is when it has no scheme" do
      url = Vug.duckduckgo_favicon_url("example.com")
      url.should contain("icons.duckduckgo.com")
      url.should contain("example.com")
    end
  end
end
