require "./crimage_helper"

module Vug
  # Validates image format detection and checks if data is a valid image.
  # Dimension extraction is in ImageDimensions (separation of concerns).
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

      return true if png?(data) || jpeg?(data) || ico?(data) || svg?(data) || webp?(data) || gif?(data)

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

    # Returns the four-character chunk type found at the first WEBP chunk
    # (offset 12..15) if available. This is a lightweight inspection used to
    # detect VP8 (lossy) vs VP8L (lossless) vs VP8X (extended) WebP images.
    private def self.webp_chunk_type(data : Bytes) : String?
      return if data.size < 16
      String.new(data[12..15])
    end

    # Returns true if the WEBP data appears to be the lossy VP8 variant.
    def self.webp_lossy?(data : Bytes) : Bool
      if t = webp_chunk_type(data)
        t == "VP8 "
      else
        false
      end
    end

    # Detects GIF87a and GIF89a formats by checking magic bytes.
    # Bytes 0-2: "GIF", byte 3: "8", byte 4: "7" or "9", byte 5: "a"
    def self.gif?(data : Bytes) : Bool
      data.size >= 6 &&
        data[0] == 0x47 &&                      # G
        data[1] == 0x49 &&                      # I
        data[2] == 0x46 &&                      # F
        data[3] == 0x38 &&                      # 8
        (data[4] == 0x37 || data[4] == 0x39) && # 7 or 9
        data[5] == 0x61                         # a
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
      CrImageHelper.with_image(data, false) do |image|
        !image.nil?
      end
    end
  end
end
