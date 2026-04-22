require "../spec_helper"
require "../../src/vug"

describe Vug::PlaceholderGenerator do
  describe ".generate_for_domain" do
    it "generates SVG for domain" do
      data, content_type = Vug::PlaceholderGenerator.generate_for_domain("example.com")
      data.size.should be > 0
      content_type.should eq("image/svg+xml")

      svg_string = String.new(data)
      svg_string.should contain("<?xml")
      svg_string.should contain("<svg")
      svg_string.should contain("E")
    end

    it "handles www domains" do
      data, _ = Vug::PlaceholderGenerator.generate_for_domain("www.test.com")
      data.size.should be > 0
      svg_string = String.new(data)
      svg_string.should contain("T")
    end
  end
end
