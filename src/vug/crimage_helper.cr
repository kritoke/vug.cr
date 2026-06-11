require "crimage"

module Vug
  # Shared helper for safely loading images via CrImage with comprehensive
  # error handling. Extracted from ImageValidator and ImageDimensions to
  # eliminate the duplicated with_crimage / with_crimage_result pattern.
  module CrImageHelper
    # Attempts to load raw bytes as a CrImage::Image and yields it.
    # Returns `default` for empty data, nil reads, or any parse error.
    def self.with_image(data : Bytes, default, & : CrImage::Image -> _)
      return default if data.empty?
      io = IO::Memory.new(data)
      image = CrImage.read(io)
      return default if image.nil?
      yield image
    rescue CrImage::Error | CrImage::UnknownFormat | IO::Error | ArgumentError | IndexError | NotImplementedError | Compress::Deflate::Error | Compress::Zlib::Error
      default
    end
  end
end
