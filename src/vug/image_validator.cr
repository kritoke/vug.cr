module Vug
  module ImageValidator
    PNG_SIGNATURE  = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    JPEG_SIGNATURE = Bytes[0xFF, 0xD8, 0xFF]
    ICO_SIGNATURE  = Bytes[0x00, 0x00]
    SVG_XML_START  = Bytes[0x3C, 0x3F, 0x78, 0x6D, 0x6C]
    SVG_TAG_START  = Bytes[0x3C, 0x73, 0x76, 0x67]
    WEBP_RIFF      = Bytes[0x52, 0x49, 0x46, 0x46]
    WEBP_WEBP      = Bytes[0x57, 0x45, 0x42, 0x50]

    def self.valid?(data : Bytes) : Bool
      return false if data.size < 4

      png?(data) || jpeg?(data) || ico?(data) || svg?(data) || webp?(data)
    end

    def self.png?(data : Bytes) : Bool
      data.size >= 8 && data[0..7] == PNG_SIGNATURE
    end

    def self.jpeg?(data : Bytes) : Bool
      data.size >= 3 && data[0..2] == JPEG_SIGNATURE
    end

    def self.ico?(data : Bytes) : Bool
      data.size >= 4 &&
        data[0] == ICO_SIGNATURE[0] &&
        data[1] == ICO_SIGNATURE[1] &&
        (data[2] == 0x01 || data[2] == 0x02) &&
        data[3] == 0x00
    end

    def self.svg?(data : Bytes) : Bool
      data.size >= 5 && (data[0..4] == SVG_XML_START || data[0..3] == SVG_TAG_START)
    end

    def self.webp?(data : Bytes) : Bool
      data.size >= 12 && data[0..3] == WEBP_RIFF && data[8..11] == WEBP_WEBP
    end

    def self.detect_content_type(data : Bytes) : String
      return "image/png" if png?(data)
      return "image/jpeg" if jpeg?(data)
      return "image/x-icon" if ico?(data)
      return "image/svg+xml" if svg?(data)
      return "image/webp" if webp?(data)
      "application/octet-stream"
    end
  end
end
