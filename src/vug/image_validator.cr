require "crimage"

module Vug
  module ImageValidator
    PNG_SIGNATURE  = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    JPEG_SIGNATURE = Bytes[0xFF, 0xD8, 0xFF]
    SVG_TAG_START  = Bytes[0x3C, 0x73, 0x76, 0x67]
    SVG_TAG_BYTES  = Bytes[0x3C, 0x73, 0x76, 0x67, 0x20, 0x3E, 0x09, 0x0A, 0x0D] # <svg followed by space, >, tab, newline
    WEBP_RIFF      = Bytes[0x52, 0x49, 0x46, 0x46]
    WEBP_WEBP      = Bytes[0x57, 0x45, 0x42, 0x50]

    # Window size (in bytes) to scan for <svg> tag after <?xml declaration.
    # 1024 bytes is sufficient to handle typical XML declarations with namespaces
    # and processing instructions before the root <svg> element.
    SVG_SCAN_WINDOW = 1024

    def self.valid?(data : Bytes, hard_validation : Bool = false) : Bool
      return false if data.size < 4

      return true if png?(data) || jpeg?(data) || ico?(data) || svg?(data) || webp?(data)

      return false unless hard_validation

      valid_via_crimage?(data)
    end

    def self.png?(data : Bytes) : Bool
      data.size >= 8 && data[0..7] == PNG_SIGNATURE
    end

    def self.jpeg?(data : Bytes) : Bool
      data.size >= 3 && data[0..2] == JPEG_SIGNATURE
    end

    def self.ico?(data : Bytes) : Bool
      data.size >= 4 &&
        data[0] == 0x00 &&
        data[1] == 0x00 &&
        (data[2] == 0x01 || data[2] == 0x02) &&
        data[3] == 0x00
    end

    SVG_DECLARATION = Bytes[0x3C, 0x3F, 0x78, 0x6D, 0x6C] # <?xml

    def self.svg?(data : Bytes) : Bool
      return false if data.size < 5

      # Direct <svg at the start
      return true if data[0..3] == SVG_TAG_START

      # <?xml declaration — must also contain <svg to be SVG, not just any XML
      if data[0..4] == SVG_DECLARATION
        return contains_svg_tag?(data)
      end

      false
    end

    def self.webp?(data : Bytes) : Bool
      data.size >= 12 && data[0..3] == WEBP_RIFF && data[8..11] == WEBP_WEBP
    end

    def self.detect_content_type(data : Bytes, hard_validation : Bool = false) : String
      return "image/png" if png?(data)
      return "image/jpeg" if jpeg?(data)
      return "image/x-icon" if ico?(data)
      return "image/svg+xml" if svg?(data)
      return "image/webp" if webp?(data)

      return "application/octet-stream" unless hard_validation

      detect_via_crimage(data)
    end

    private def self.with_crimage_result(data : Bytes, default, & : CrImage::Image -> _)
      return default if data.empty?
      io = IO::Memory.new(data)
      image = CrImage.read(io)
      return default if image.nil?
      yield image
    rescue CrImage::Error | CrImage::UnknownFormat | IO::Error | ArgumentError | IndexError | NotImplementedError | Compress::Deflate::Error | Compress::Zlib::Error
      default
    end

    def self.get_image_dimensions(data : Bytes) : {Int32, Int32}?
      return if data.size < 4

      if png?(data)
        return read_png_dimensions(data)
      elsif jpeg?(data)
        return scan_jpeg_dimensions(data)
      elsif webp?(data)
        return read_webp_dimensions(data)
      elsif ico?(data)
        return read_ico_dimensions(data)
      elsif gif?(data)
        return read_gif_dimensions(data)
      end

      with_crimage_result(data, nil) do |image|
        {image.bounds.width, image.bounds.height}
      end
    end

    private def self.gif?(data : Bytes) : Bool
      data.size >= 6 &&
        (data[0..2] == Bytes[0x47, 0x49, 0x46, 0x38, 0x37, 0x61][0..2] ||
          data[0..2] == Bytes[0x47, 0x49, 0x46, 0x38, 0x39, 0x61][0..2]) &&
        data[3] == 0x38 &&
        (data[4] == 0x37 || data[4] == 0x39) &&
        data[5] == 0x61
    end

    private def self.read_png_dimensions(data : Bytes) : {Int32, Int32}?
      return unless data.size >= 24
      w = (data[16].to_u32 << 24) | (data[17].to_u32 << 16) | (data[18].to_u32 << 8) | data[19].to_u32
      h = (data[20].to_u32 << 24) | (data[21].to_u32 << 16) | (data[22].to_u32 << 8) | data[23].to_u32
      {w.to_i32!, h.to_i32!}
    end

    private def self.scan_jpeg_dimensions(data : Bytes) : {Int32, Int32}?
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

    private def self.read_gif_dimensions(data : Bytes) : {Int32, Int32}?
      return unless data.size >= 10
      w = data[6].to_i32 | (data[7].to_i32 << 8)
      h = data[8].to_i32 | (data[9].to_i32 << 8)
      {w, h}
    end

    private def self.read_webp_dimensions(data : Bytes) : {Int32, Int32}?
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

    private def self.read_ico_dimensions(data : Bytes) : {Int32, Int32}?
      return unless data.size >= 18
      num_images = (data[4].to_u32 << 8) | data[5].to_u32
      return if num_images == 0

      w_raw = data[6]
      h_raw = data[7]
      w = w_raw == 0 ? 256 : w_raw.to_i32
      h = h_raw == 0 ? 256 : h_raw.to_i32
      {w, h}
    end

    private def self.contains_svg_tag?(data : Bytes) : Bool
      # Scan a reasonable window after <?xml for the <svg element
      limit = Math.min(data.size, SVG_SCAN_WINDOW)
      i = 0

      while i < limit - 4
        if data[i] == 0x3C &&     # <
           data[i + 1] == 0x73 && # s
           data[i + 2] == 0x76 && # v
           data[i + 3] == 0x67    # g
          # Verify next byte is a valid tag separator
          if i + 4 < limit
            next_byte = data[i + 4]
            return true if SVG_TAG_BYTES.includes?(next_byte)
          end
        end
        i += 1
      end

      false
    end

    private def self.valid_via_crimage?(data : Bytes) : Bool
      with_crimage_result(data, false) do |image|
        !image.nil?
      end
    end

    private def self.detect_via_crimage(data : Bytes) : String
      with_crimage_result(data, "application/octet-stream") do |image|
        if image.is_a?(CrImage::RGBA) || image.is_a?(CrImage::NRGBA)
          "image/png"
        elsif image.is_a?(CrImage::Gray)
          "image/jpeg"
        else
          "application/octet-stream"
        end
      end
    end
  end
end
