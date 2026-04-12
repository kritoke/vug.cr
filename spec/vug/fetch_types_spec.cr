require "../spec_helper"
require "../../src/vug/fetch_types"

describe Vug::FetchSuccess do
  it "constructs and exposes fields" do
    s = Vug::FetchSuccess.new("u", "/p", "image/png", 200, 16, 16)
    s.fetched_url.should eq("u")
    s.path.should eq("/p")
    s.content_type.should eq("image/png")
    s.status_code.should eq(200)
    s.width.should eq(16)
    s.height.should eq(16)
  end
end

describe Vug::FetchError do
  it "constructs and exposes fields" do
    e = Vug::FetchError.new("u", :io_error, "boom")
    e.target_url.should eq("u")
    e.error_type.should eq(:io_error)
    e.message.should eq("boom")
  end
end
