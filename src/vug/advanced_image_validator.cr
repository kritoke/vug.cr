require "crimage"

module Vug
  # Enhanced image validator using crimage for proper image validation
  # beyond just header checks
  module AdvancedImageValidator
    def self.valid?(data : Bytes) : Bool
      return false if data.size == 0

      begin
        io = IO::Memory.new(data)
        image = CrImage.read(io)
        !image.nil?
      rescue
        false
      end
    end

    def self.detect_content_type(data : Bytes) : String
      return "application/octet-stream" if data.size == 0

      begin
        io = IO::Memory.new(data)
        image = CrImage.read(io)

        return "application/octet-stream" if image.nil?

        basic_type = ImageValidator.detect_content_type(data)
        return basic_type if basic_type != "application/octet-stream"

        if image.is_a?(CrImage::RGBA) || image.is_a?(CrImage::NRGBA)
          "image/png"
        elsif image.is_a?(CrImage::Gray)
          "image/jpeg"
        else
          "image/unknown"
        end
      rescue
        "application/octet-stream"
      end
    end

    def self.get_image_dimensions(data : Bytes) : {Int32, Int32}?
      return if data.size == 0

      begin
        io = IO::Memory.new(data)
        image = CrImage.read(io)
        return if image.nil?
        {image.width, image.height}
      rescue
        nil
      end
    end
  end
end
