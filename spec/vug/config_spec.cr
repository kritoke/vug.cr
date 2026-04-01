require "../spec_helper"
require "../../src/vug"

describe Vug::Config do
  it "has default values" do
    config = Vug::Config.new
    config.timeout.should eq(30.seconds)
    config.max_redirects.should eq(10)
    config.max_size.should eq(100 * 1024)
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
