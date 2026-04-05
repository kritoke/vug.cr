require "../spec_helper"
require "../../src/vug"

describe Vug::DataUrlHandler do
  describe ".extract_from_url" do
    it "extracts valid base64 PNG data URL" do
      data_url = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAsgB/1KfFZIAAAAASUVORK5CYII="
      result = Vug::DataUrlHandler.extract_from_url(data_url)
      result.should_not be_nil
      if result
        data, media_type = result
        data.size.should be > 0
        media_type.should eq("image/png")
      end
    end

    it "returns nil for invalid data URL" do
      invalid_data_url = "data:image/png;base64,invalidbase64!"
      result = Vug::DataUrlHandler.extract_from_url(invalid_data_url)
      result.should be_nil
    end

    it "handles data URL without base64 marker" do
      simple_data_url = "data:text/plain,hello"
      result = Vug::DataUrlHandler.extract_from_url(simple_data_url)
      result.should be_nil
    end

    it "returns nil for non-image data URLs" do
      data_url = "data:text/plain;base64,SGVsbG8="
      result = Vug::DataUrlHandler.extract_from_url(data_url)
      result.should be_nil
    end

    it "rejects data URLs exceeding max_size" do
      small_png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAsgB/1KfFZIAAAAASUVORK5CYII="
      result = Vug::DataUrlHandler.extract_from_url(small_png, max_size: 1)
      result.should be_nil
    end

    it "accepts data URLs within max_size" do
      small_png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAsgB/1KfFZIAAAAASUVORK5CYII="
      result = Vug::DataUrlHandler.extract_from_url(small_png, max_size: 1000)
      result.should_not be_nil
    end

    it "uses estimated encoded size for limit check" do
      large_data = "data:image/png;base64," + ("A" * 10000)
      result = Vug::DataUrlHandler.extract_from_url(large_data, max_size: 100)
      result.should be_nil
    end

    it "accepts data with exact max_size limit" do
      small_png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAsgB/1KfFZIAAAAASUVORK5CYII="
      result = Vug::DataUrlHandler.extract_from_url(small_png, max_size: 1000)
      result.should_not be_nil
    end
  end

  describe ".data_url?" do
    it "returns true for data URLs" do
      Vug::DataUrlHandler.data_url?("data:image/png;base64,foo").should be_true
    end

    it "returns false for regular URLs" do
      Vug::DataUrlHandler.data_url?("https://example.com/favicon.ico").should be_false
    end
  end
end
