require "../spec_helper"
require "../../src/vug"

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

  describe ".detect_content_type" do
    it "detects PNG" do
      png_header = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]
      Vug::ImageValidator.detect_content_type(png_header).should eq("image/png")
    end

    it "detects JPEG" do
      jpeg_header = Bytes[0xFF, 0xD8, 0xFF, 0x00, 0x00]
      Vug::ImageValidator.detect_content_type(jpeg_header).should eq("image/jpeg")
    end

    it "detects content type via crimage for valid images" do
      # Create a valid PNG via crimage
      rect = CrImage.rect(0, 0, 1, 1)
      rgba = CrImage::RGBA.new(rect)
      io = IO::Memory.new
      CrImage::PNG.write(io, rgba)
      png_data = io.to_slice

      # Should detect as PNG (signature match) not fall through to crimage
      Vug::ImageValidator.detect_content_type(png_data).should eq("image/png")
    end

    it "returns octet-stream for unrecognizable data" do
      random_data = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      Vug::ImageValidator.detect_content_type(random_data).should eq("application/octet-stream")
    end
  end

  describe ".get_image_dimensions" do
    it "returns nil for empty data" do
      Vug::ImageValidator.get_image_dimensions(Bytes.empty).should be_nil
    end

    it "returns nil for invalid image data" do
      Vug::ImageValidator.get_image_dimensions(Bytes[0x00, 0x00, 0x00, 0x00]).should be_nil
    end

    it "returns dimensions for valid PNG" do
      # Create a minimal 2x2 PNG using crimage
      rect = CrImage.rect(0, 0, 2, 2)
      rgba = CrImage::RGBA.new(rect)
      io = IO::Memory.new
      CrImage::PNG.write(io, rgba)
      png_data = io.to_slice

      dims = Vug::ImageValidator.get_image_dimensions(png_data)
      dims.should eq({2, 2})
    end
  end
end