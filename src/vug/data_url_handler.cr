require "base64"
require "./image_validator"

module Vug
  # Handles base64-encoded data URLs in favicon href attributes
  # Example: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...
  module DataUrlHandler
    def self.extract_from_url(data_url : String, max_size : Int32? = nil) : {Bytes, String}?
      return unless data_url.starts_with?("data:")

      if data_url.includes?(",")
        parts = data_url.split(",", 2)
        header = parts[0]
        encoded_data = parts[1]

        is_base64 = false

        media_type = if header.includes?(";")
                       header_parts = header.split(";", 2)
                       is_base64 = header_parts[1] == "base64"
                       header_parts[0].sub("data:", "")
                     else
                       header.sub("data:", "")
                     end

        if max_size && encoded_data.size > max_size * 4 / 3
          return
        end

        begin
          decoded_data = is_base64 ? Base64.decode(encoded_data) : encoded_data.to_slice

          if max_size && decoded_data.size > max_size
            return
          end

          if ImageValidator.valid?(decoded_data)
            return {decoded_data, media_type}
          end
        rescue
        end
      end

      nil
    end

    def self.data_url?(url : String) : Bool
      url.starts_with?("data:")
    end
  end
end
