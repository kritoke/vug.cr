require "../spec_helper"
require "../../src/vug"

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

    it "handles www prefix" do
      url = Vug::Fetcher.google_favicon_url("www.example.com")
      url.should eq("https://www.google.com/s2/favicons?domain=www.example.com&sz=256")
    end
  end

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
end
