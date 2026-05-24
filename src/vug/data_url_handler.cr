require "base64"
require "./image_validator"

module Vug
  # Handles base64-encoded data URLs in favicon href attributes
  # Example: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...
  module DataUrlHandler
    def self.extract_from_url(data_url : String, max_size : Int32? = nil) : {Bytes, String}?
      return unless data_url.starts_with?("data:") && data_url.includes?(",")

      header, encoded_data = split_data_url(data_url)
      media_type, is_base64 = parse_data_header(header)

      return if exceeds_max_encoded_size?(encoded_data, max_size)
      return unless decoded_data = try_decode_data(encoded_data, is_base64, max_size)
      return unless ImageValidator.valid?(decoded_data)

      {decoded_data, media_type}
    rescue Base64::Error
      nil
    end

    def self.data_url?(url : String) : Bool
      url.starts_with?("data:")
    end

    private def self.split_data_url(data_url : String) : {String, String}
      parts = data_url.split(",", 2)
      {parts[0], parts[1]}
    end

    private def self.parse_data_header(header : String) : {String, Bool}
      if header.includes?(";")
        header_parts = header.split(";", 2)
        is_base64 = header_parts[1] == "base64"
        media_type = header_parts[0].sub("data:", "")
        {media_type, is_base64}
      else
        {header.sub("data:", ""), false}
      end
    end

    private def self.exceeds_max_encoded_size?(encoded_data : String, max_size : Int32?) : Bool
      return false unless max_size
      encoded_data.size > ((max_size * 4) / 3.0).ceil.to_i
    end

    private def self.try_decode_data(encoded_data : String, is_base64 : Bool, max_size : Int32?) : Bytes?
      decoded_data = is_base64 ? Base64.decode(encoded_data) : encoded_data.to_slice
      return if max_size && decoded_data.size > max_size
      decoded_data
    end
  end
end
