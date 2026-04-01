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

      @favicons.find(&.has_any_size?) ||
        @favicons.max_by? { |favicon| favicon.size_pixels || 0 } ||
        @favicons.first?
    end

    # Get favicon closest to preferred size (e.g., "32x32")
    def by_preferred_size(preferred_width : Int32, preferred_height : Int32) : FaviconInfo?
      return if @favicons.empty?

      target_area = preferred_width * preferred_height
      @favicons.find(&.has_any_size?) ||
        @favicons.min_by? { |favicon| (favicon.size_pixels - target_area).abs } ||
        best
    end
  end
end
