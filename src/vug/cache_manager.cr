require "./config"
require "./cache"

module Vug
  class CacheManager
    def initialize(@config : Config, @memory_cache : MemoryCache? = nil)
    end

    def get(url : String) : String?
      # Check config-based storage first
      if cached = @config.load(url)
        return cached
      end

      # Fall back to memory cache
      @memory_cache.try(&.get(url))
    end

    def set(url : String, local_path : String) : Nil
      # Only store absolute paths in memory cache
      return unless local_path.starts_with?("/")

      # Store in memory cache if available
      @memory_cache.try(&.set(url, local_path))
    end
  end
end
