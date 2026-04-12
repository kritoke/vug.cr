require "../spec_helper"
require "../../src/vug/image_processor"
require "../../src/vug/config"

describe Vug::ImageProcessor::Default do
  it "processes valid image bytes and saves via config" do
    # Use a PNG signature to satisfy ImageValidator.png?
    data = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    saved = false
    cfg = Vug::Config.new(on_save: ->(_url : String, _data : Bytes, _ct : String) { saved = true; "/tmp/saved.png".as(String?) })
    processor = Vug::ImageProcessor::Default.new(cfg, nil)

    result = processor.process_bytes("https://example.com/favicon.ico", data, "image/png")
    result.success?.should be_true
    result.local_path.should eq("/tmp/saved.png")
    saved.should be_true
  end

  it "returns failure when save returns nil" do
    data = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    cfg = Vug::Config.new(on_save: ->(_url : String, _data : Bytes, _ct : String) : String? { nil })
    processor = Vug::ImageProcessor::Default.new(cfg, nil)

    result = processor.process_bytes("https://example.com/favicon.ico", data, "image/png")
    result.failure?.should be_true
    result.error_type.should eq(Vug::ErrorType::SaveFailed)
  end

  it "returns invalid_image for non-image bytes" do
    data = Bytes[0x00, 0x01, 0x02]
    cfg = Vug::Config.new(on_save: ->(_url : String, _data : Bytes, _ct : String) : String? { "/tmp/x".as(String?) })
    processor = Vug::ImageProcessor::Default.new(cfg, nil)

    result = processor.process_bytes("https://example.com/favicon.ico", data, "application/octet-stream")
    result.failure?.should be_true
    result.error_type.should eq(Vug::ErrorType::InvalidImage)
  end
end
