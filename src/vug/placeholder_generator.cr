require "digest"
require "html"
require "base64"

module Vug
  # Generates default SVG favicons when no real favicon is found
  # Creates a simple colored circle with the first letter of the domain
  module PlaceholderGenerator
    # DJB2 hash seed constant (Daniel J. Bernstein)
    HASH_SEED = 5381_u64

    # SVG placeholder dimensions
    SVG_SIZE      = 256
    CORNER_RADIUS =  20
    CIRCLE_RADIUS =  90
    FONT_SIZE     = 120
    TEXT_Y_OFFSET = 156

    # Color palette for different domains (consistent based on domain hash)
    COLORS = [
      "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FECA57",
      "#FF9FF3", "#54A0FF", "#5F27CD", "#00D2D3", "#FF9F43",
      "#10AC84", "#EE5A24", "#0ABDE3", "#BE6DA7", "#A3CB38",
    ]

    def self.generate_for_domain(domain : String) : {Bytes, String}
      # Handle empty or whitespace-only domains
      clean_domain = domain.strip
      if clean_domain.empty?
        clean_domain = "?"
      else
        # Get first letter of domain (excluding www, etc.)
        clean_domain = clean_domain.downcase
        if clean_domain.starts_with?("www.")
          clean_domain = clean_domain[4..-1]
          clean_domain = "?" if clean_domain.empty?
        end
      end

      raw_char = clean_domain.chars.first?.try(&.upcase.to_s) || "?"
      first_char = HTML.escape(raw_char)

      # Generate consistent color based on domain using DJB2 hash
      hash_value = HASH_SEED
      clean_domain.each_char do |char|
        hash_value = ((hash_value << 5) &+ hash_value) &+ char.ord.to_u64
      end
      color_index = (hash_value % COLORS.size).to_i
      background_color = COLORS[color_index]

      # Create SVG content
      svg_content = <<-SVG
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="#{SVG_SIZE}" height="#{SVG_SIZE}" viewBox="0 0 #{SVG_SIZE} #{SVG_SIZE}">
          <rect width="#{SVG_SIZE}" height="#{SVG_SIZE}" fill="#ffffff" rx="#{CORNER_RADIUS}"/>
          <circle cx="#{SVG_SIZE // 2}" cy="#{SVG_SIZE // 2}" r="#{CIRCLE_RADIUS}" fill="#{background_color}"/>
          <text x="#{SVG_SIZE // 2}" y="#{TEXT_Y_OFFSET}" font-family="Arial, sans-serif" font-size="#{FONT_SIZE}" font-weight="bold" text-anchor="middle" fill="white" dominant-baseline="middle">#{first_char}</text>
        </svg>
        SVG

      {svg_content.to_slice, "image/svg+xml"}
    end
  end
end
