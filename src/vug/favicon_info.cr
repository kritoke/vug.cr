module Vug
  # Represents a favicon entry from HTML, manifest, or other sources
  record FaviconInfo,
    url : String,
    sizes : String?,
    type : String?,
    purpose : String? do
    def size_pixels : Int32?
      size_val = sizes
      return if size_val.nil? || size_val == "any"

      size_list = size_val.split(' ')
      max_size = 0

      size_list.each do |size_str|
        if size_str.includes?('x')
          parts = size_str.split('x')
          if parts.size == 2
            begin
              width = parts[0].to_i
              height = parts[1].to_i
              area = width * height
              max_size = [max_size, area].max
            rescue
              # Skip invalid size format
            end
          end
        end
      end

      max_size > 0 ? max_size : nil
    end

    def has_any_size? : Bool
      sizes == "any"
    end
  end
end
