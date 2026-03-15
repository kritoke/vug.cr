require "digest"

module Vug
  # Generates default SVG favicons when no real favicon is found
  # Creates a simple colored circle with the first letter of the domain
  module PlaceholderGenerator
    # Color palette for different domains (consistent based on domain hash)
    COLORS = [
      "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FECA57",
      "#FF9FF3", "#54A0FF", "#5F27CD", "#00D2D3", "#FF9F43",
      "#10AC84", "#EE5A24", "#0ABDE3", "#BE6DA7", "#A3CB38",
    ]

    def self.generate_for_domain(domain : String) : {Bytes, String}
      # Get first letter of domain (excluding www, etc.)
      clean_domain = domain.downcase
      if clean_domain.starts_with?("www.")
        clean_domain = clean_domain[4..-1]
      end

      first_char = clean_domain.chars.first?.try(&.upcase) || "?"

      # Generate consistent color based on domain - use simple hash
      # Convert domain to a number by summing character codes
      hash_value = 0
      clean_domain.each_char do |char|
        hash_value += char.ord
      end
      color_index = hash_value % COLORS.size
      background_color = COLORS[color_index]

      # Create SVG content
      svg_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"256\" height=\"256\" viewBox=\"0 0 256 256\">\n" +
                    "  <rect width=\"256\" height=\"256\" fill=\"#ffffff\" rx=\"20\"/>\n" +
                    "  <circle cx=\"128\" cy=\"128\" r=\"90\" fill=\"#{background_color}\"/>\n" +
                    "  <text x=\"128\" y=\"156\" font-family=\"Arial, sans-serif\" font-size=\"120\" font-weight=\"bold\" text-anchor=\"middle\" fill=\"white\" dominant-baseline=\"middle\">#{first_char}</text>\n" +
                    "</svg>"

      {svg_content.to_slice, "image/svg+xml"}
    end

    def self.generate_favicon_url(domain : String) : String
      # Create a data URL for the generated SVG
      data, _ = generate_for_domain(domain)
      encoded_data = Base64.encode(data)
      "data:image/svg+xml;base64,#{encoded_data}"
    end
  end
end
