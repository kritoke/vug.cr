require "../spec_helper"
require "../../src/vug"

describe Vug::Config do
  it "has default values" do
    config = Vug::Config.new
    config.timeout.should eq(30.seconds)
    config.max_redirects.should eq(10)
    config.max_size.should eq(100 * 1024)
  end

  it "has default retry values" do
    config = Vug::Config.new
    config.max_retries.should eq(2)
    config.retry_base_delay.should eq(500.milliseconds)
    config.retry_max_delay.should eq(5.seconds)
  end

  it "has default html_fetch_timeout" do
    config = Vug::Config.new
    config.html_fetch_timeout.should eq(60.seconds)
  end

  it "allows custom retry settings" do
    config = Vug::Config.new(
      max_retries: 5,
      retry_base_delay: 1.seconds,
      retry_max_delay: 10.seconds
    )
    config.max_retries.should eq(5)
    config.retry_base_delay.should eq(1.seconds)
    config.retry_max_delay.should eq(10.seconds)
  end

  it "allows custom html_fetch_timeout" do
    config = Vug::Config.new(html_fetch_timeout: 120.seconds)
    config.html_fetch_timeout.should eq(120.seconds)
  end

  it "allows callback assignment" do
    debug_messages = [] of String
    config = Vug::Config.new(
      on_debug: ->(msg : String) { debug_messages << msg }
    )
    config.debug("test message")
    debug_messages.should eq(["test message"])
  end

  describe "structured logging" do
    it "emits LogEntry to on_log callback on debug" do
      entries = [] of Vug::LogEntry
      config = Vug::Config.new(
        on_log: ->(entry : Vug::LogEntry) { entries << entry; nil }
      )
      config.debug("test debug")
      entries.size.should eq(1)
      entries[0].level.should eq(Vug::LogLevel::Debug)
      entries[0].message.should eq("test debug")
      entries[0].context.should be_nil
    end

    it "emits LogEntry with context on error" do
      entries = [] of Vug::LogEntry
      config = Vug::Config.new(
        on_log: ->(entry : Vug::LogEntry) { entries << entry; nil }
      )
      config.error("ctx", "test error")
      entries.size.should eq(1)
      entries[0].level.should eq(Vug::LogLevel::Error)
      entries[0].message.should eq("test error")
      entries[0].context.should eq("ctx")
    end

    it "emits LogEntry on warning" do
      entries = [] of Vug::LogEntry
      config = Vug::Config.new(
        on_log: ->(entry : Vug::LogEntry) { entries << entry; nil }
      )
      config.warning("test warn")
      entries.size.should eq(1)
      entries[0].level.should eq(Vug::LogLevel::Warn)
    end

    it "fires both legacy and structured callbacks" do
      legacy = [] of String
      structured = [] of Vug::LogEntry
      config = Vug::Config.new(
        on_debug: ->(msg : String) { legacy << msg },
        on_log: ->(entry : Vug::LogEntry) { structured << entry; nil },
      )
      config.debug("both")
      legacy.should eq(["both"])
      structured.size.should eq(1)
    end

    it "produces valid JSON from LogEntry" do
      entry = Vug::LogEntry.new(Vug::LogLevel::Error, "disk full", "db-writer")
      json = entry.to_json
      json.should contain("\"level\":\"error\"")
      json.should contain("\"message\":\"disk full\"")
      json.should contain("\"context\":\"db-writer\"")
      json.should contain("timestamp")
    end

    it "produces JSON without context when nil" do
      entry = Vug::LogEntry.new(Vug::LogLevel::Debug, "hello")
      json = entry.to_json
      json.should contain("\"level\":\"debug\"")
      json.should_not contain("context")
    end

    it "supports copy_with with on_log" do
      entries = [] of Vug::LogEntry
      original = Vug::Config.new
      copy = original.copy_with(
        on_log: ->(entry : Vug::LogEntry) { entries << entry; nil }
      )
      copy.debug("via copy")
      entries.size.should eq(1)
    end
  end
end
