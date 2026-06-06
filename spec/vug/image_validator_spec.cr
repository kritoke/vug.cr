require "../spec_helper"
require "../../src/vug"
require "../../src/vug/image_dimensions"

describe Vug::ImageValidator do
  describe ".valid?" do
    it "identifies PNG images" do
      png_header = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]
      Vug::ImageValidator.valid?(png_header).should be_true
    end

    it "identifies JPEG images" do
      jpeg_header = Bytes[0xFF, 0xD8, 0xFF, 0x00, 0x00]
      Vug::ImageValidator.valid?(jpeg_header).should be_true
    end

    it "identifies ICO images" do
      ico_header = Bytes[0x00, 0x00, 0x01, 0x00, 0x00]
      Vug::ImageValidator.valid?(ico_header).should be_true
    end

    it "rejects invalid data" do
      invalid = Bytes[0x00, 0x00, 0x00, 0x00]
      Vug::ImageValidator.valid?(invalid).should be_false
    end

    it "rejects small data" do
      small = Bytes[0x00]
      Vug::ImageValidator.valid?(small).should be_false
    end

    it "validates via crimage for non-signature formats" do
      # Create a valid PNG via crimage to exercise the crimage path
      rect = CrImage.rect(0, 0, 1, 1)
      rgba = CrImage::RGBA.new(rect)
      io = IO::Memory.new
      CrImage::PNG.write(io, rgba)
      png_data = io.to_slice

      # This exercises both signature check AND crimage validation
      Vug::ImageValidator.valid?(png_data).should be_true
    end
  end

  describe ".svg?" do
    it "detects SVG with XML declaration followed by svg tag" do
      # <?xml version="1.0"?>\n<svg xmlns="...
      svg_data = "<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\">".to_slice
      Vug::ImageValidator.svg?(svg_data).should be_true
    end

    it "detects SVG with svg tag at start" do
      svg_data = Bytes[0x3C, 0x73, 0x76, 0x67, 0x20]
      Vug::ImageValidator.svg?(svg_data).should be_true
    end

    it "rejects non-SVG XML starting with <?xml" do
      # <?xml version="1.0"?>\n<root>... — this is XML but not SVG
      xml_data = "<?xml version=\"1.0\"?>\n<root><item>hello</item></root>".to_slice
      Vug::ImageValidator.svg?(xml_data).should be_false
    end

    it "rejects short data" do
      Vug::ImageValidator.svg?(Bytes[0x3C, 0x3F, 0x78]).should be_false
    end
  end

  describe ".webp?" do
    it "detects WEBP format" do
      webp_data = Bytes[0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]
      Vug::ImageValidator.webp?(webp_data).should be_true
    end

    it "rejects incomplete WEBP" do
      Vug::ImageValidator.webp?(Bytes[0x52, 0x49, 0x46, 0x46, 0x00, 0x00]).should be_false
    end
  end
end
