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
  end
end
