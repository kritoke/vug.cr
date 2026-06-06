require "../spec_helper"
require "../../src/vug/image_dimensions"

describe Vug::ImageDimensions do
  describe ".get" do
    it "returns nil for empty data" do
      Vug::ImageDimensions.get(Bytes.empty).should be_nil
    end

    it "returns nil for invalid image data" do
      Vug::ImageDimensions.get(Bytes[0x00, 0x00, 0x00, 0x00]).should be_nil
    end

    it "returns dimensions for valid PNG" do
      # Create a minimal 2x2 PNG using crimage
      rect = CrImage.rect(0, 0, 2, 2)
      rgba = CrImage::RGBA.new(rect)
      io = IO::Memory.new
      CrImage::PNG.write(io, rgba)
      png_data = io.to_slice

      dims = Vug::ImageDimensions.get(png_data)
      dims.should eq({2, 2})
    end
  end
end
