require "base64"
require "./image_validator"

module Vug
  # Handles base64-encoded data URLs in favicon href attributes
  # Example: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...
  module DataUrlHandler
    def self.extract_from_url(data_url : String) : {Bytes, String}?
      return unless data_url.starts_with?("data:")

      # Parse data URL format: data:[<mediatype>][;base64],<data>
      if data_url.includes?(",")
        parts = data_url.split(",", 2)
        header = parts[0]
        encoded_data = parts[1]

        # Extract media type and check if it's base64
        is_base64 = false

        media_type = if header.includes?(";")
                       header_parts = header.split(";", 2)
                       is_base64 = header_parts[1] == "base64"
                       header_parts[0].sub("data:", "")
                     else
                       header.sub("data:", "")
                     end

        begin
          decoded_data = is_base64 ? Base64.decode(encoded_data) : encoded_data.to_slice

          # Validate that it's actually an image
          if ImageValidator.valid?(decoded_data)
            return {decoded_data, media_type}
          end
        rescue
          # Invalid base64 or other decoding error
        end
      end

      nil
    end

    def self.data_url?(url : String) : Bool
      url.starts_with?("data:")
    end
  end
end
