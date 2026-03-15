module Vug
  class FaviconCollection
    @favicons : Array(FaviconInfo)

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

    # Returns the best favicon based on size and quality
    def best : FaviconInfo?
      return if @favicons.empty?

      # Sort by preference: any size > largest pixel area > first found
      sorted = @favicons.sort_by do |favicon|
        if favicon.has_any_size?
          {0, 0} # Highest priority: "any" size sorts first
        elsif size_pixels = favicon.size_pixels
          {1, -size_pixels} # Second priority: larger sizes first
        else
          {2, 0} # Lowest priority: unknown size
        end
      end

      sorted.first?
    end

    # Returns the largest favicon by pixel area
    def largest : FaviconInfo?
      return if @favicons.empty?

      largest_favicon = nil
      max_area = 0

      @favicons.each do |favicon|
        if favicon.has_any_size?
          return favicon # "any" size is considered largest
        end

        if size_pixels = favicon.size_pixels
          if size_pixels > max_area
            max_area = size_pixels
            largest_favicon = favicon
          end
        end
      end

      largest_favicon || @favicons.first?
    end

    # Get favicon closest to preferred size (e.g., "32x32")
    def by_preferred_size(preferred_width : Int32, preferred_height : Int32) : FaviconInfo?
      return if @favicons.empty?

      target_area = preferred_width * preferred_height
      best_match = nil
      min_diff = Int32::MAX

      @favicons.each do |favicon|
        if favicon.has_any_size?
          return favicon # "any" size matches any preference
        end

        if size_pixels = favicon.size_pixels
          diff = (size_pixels - target_area).abs
          if diff < min_diff
            min_diff = diff
            best_match = favicon
          end
        end
      end

      best_match || best # Fallback to best available
    end
  end
end
