module Vug
  class FaviconCollection
    @favicons : Array(FaviconInfo)

    # URLs or patterns that indicate this is likely a logo, not a favicon.
    # Favicons are typically 16x16, 32x32, 48x48 - logos are usually much larger.
    LOGO_INDICATORS = [
      "logo",
      "channel",
      "brand",
      "header",
      "banner",
      "profile",
      "avatar",
      "artwork",
    ]

    def initialize
      @favicons = [] of FaviconInfo
    end

    def add(favicon : FaviconInfo)
      @favicons << favicon
    end

    def add_all(favicons : Array(FaviconInfo))
      @favicons.concat(favicons)
    end

    def empty? : Bool
      @favicons.empty?
    end

    def size : Int32
      @favicons.size
    end

    def all : Array(FaviconInfo)
      @favicons.clone
    end

    # Returns the best favicon based on quality heuristics.
    # Favicons should be small (32x32 or similar), not large logos.
    def best : FaviconInfo?
      return if @favicons.empty?

      # Filter out likely logos (URLs containing logo/channel/brand/etc)
      non_logos = @favicons.reject { |f| likely_logo?(f.url) }

      candidates = non_logos.empty? ? @favicons : non_logos

      # Sort by preference: any size > reasonable size (not massive) > largest pixel area > first found
      sorted = candidates.sort_by do |favicon|
        if favicon.has_any_size?
          {0, 0} # Highest priority: "any" size
        elsif size_pixels = favicon.size_pixels
          # Prefer smaller images for favicons (16-64px range is typical)
          # Large images (logo-sized) get lower priority
          if size_pixels > 128 * 128
            {2, -size_pixels} # Lower priority: too large, likely a logo
          else
            {1, -size_pixels} # Normal priority: reasonable size
          end
        else
          {3, 0} # Lowest priority: unknown size
        end
      end

      sorted.first?
    end

    private def likely_logo?(url : String) : Bool
      url_downcase = url.downcase
      LOGO_INDICATORS.any? { |indicator| url_downcase.includes?(indicator) }
    end
  end
end
