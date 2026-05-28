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
end
