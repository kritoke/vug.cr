require "crimage"
require "./image_validator"

module Vug
  # Extracts image dimensions from raw bytes for various image formats.
  # Supports PNG, JPEG, WebP, ICO, GIF, and falls back to CrImage for others.
  module ImageDimensions
    # Get image dimensions from raw bytes.
    # Returns {width, height} or nil if dimensions cannot be determined.
    def self.get(data : Bytes) : {Int32, Int32}?
      return if data.size < 4

      if ImageValidator.png?(data)
        return read_png(data)
      elsif ImageValidator.jpeg?(data)
        return read_jpeg(data)
      elsif ImageValidator.webp?(data)
        return read_webp(data)
      elsif ImageValidator.ico?(data)
        return read_ico(data)
      elsif ImageValidator.gif?(data)
        return read_gif(data)
      end

      with_crimage(data, nil) do |image|
        {image.bounds.width, image.bounds.height}
      end
    end

    private def self.read_png(data : Bytes) : {Int32, Int32}?
      return unless data.size >= 24
      w = (data[16].to_u32 << 24) | (data[17].to_u32 << 16) | (data[18].to_u32 << 8) | data[19].to_u32
      h = (data[20].to_u32 << 24) | (data[21].to_u32 << 16) | (data[22].to_u32 << 8) | data[23].to_u32
      {w.to_i32, h.to_i32}
    end

    private def self.read_jpeg(data : Bytes) : {Int32, Int32}?
      return if data.size < 11
      i = 2
      while i < data.size - 9
        break unless data[i] == 0xFF
        marker = data[i + 1]
        i += 2

        case marker
        when 0xC0..0xC3, 0xC5..0xC7, 0xC9..0xCB, 0xCD..0xCF
          return unless data.size >= i + 7
          h = (data[i + 3].to_u32 << 8) | data[i + 4].to_u32
          w = (data[i + 5].to_u32 << 8) | data[i + 6].to_u32
          return {w.to_i32!, h.to_i32!}
        when 0xD0..0xD7, 0x01, 0xD8, 0xD9
          next
        when 0xFF
          i -= 1
          next
        else
          return unless data.size >= i + 2
          seg_len = (data[i].to_u32 << 8) | data[i + 1].to_u32
          return if seg_len < 2
          i += seg_len
        end
      end
      nil
    end

    private def self.read_webp(data : Bytes) : {Int32, Int32}?
      return unless data.size >= 30

      chunk_type = String.new(data[12..15])
      case chunk_type
      when "VP8 "
        return unless data.size >= 30
        w = (data[26].to_u32 | (data[27].to_u32 << 8)) & 0x3FFF
        h = (data[28].to_u32 | (data[29].to_u32 << 8)) & 0x3FFF
        {w.to_i32!, h.to_i32!}
      when "VP8L"
        return unless data.size >= 25
        bits = data[21].to_u32 | (data[22].to_u32 << 8) | (data[23].to_u32 << 16) | (data[24].to_u32 << 24)
        w = (bits & 0x3FFF) + 1
        h = ((bits >> 14) & 0x3FFF) + 1
        {w.to_i32!, h.to_i32!}
      when "VP8X"
        return unless data.size >= 24
        w = (data[24].to_u32 | (data[25].to_u32 << 8) | (data[26].to_u32 << 16)) + 1
        h = (data[27].to_u32 | (data[28].to_u32 << 8) | (data[29].to_u32 << 16)) + 1
        {w.to_i32!, h.to_i32!}
      end
    end

    private def self.read_ico(data : Bytes) : {Int32, Int32}?
      return unless data.size >= 18
      num_images = (data[4].to_u32 << 8) | data[5].to_u32
      return if num_images == 0

      w_raw = data[6]
      h_raw = data[7]
      w = w_raw == 0 ? 256 : w_raw.to_i32
      h = h_raw == 0 ? 256 : h_raw.to_i32
      {w, h}
    end

    private def self.read_gif(data : Bytes) : {Int32, Int32}?
      return unless data.size >= 10
      w = data[6].to_i32 | (data[7].to_i32 << 8)
      h = data[8].to_i32 | (data[9].to_i32 << 8)
      {w, h}
    end

    private def self.with_crimage(data : Bytes, default, & : CrImage::Image -> _)
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
