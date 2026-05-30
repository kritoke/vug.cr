require "./config"
require "./cache"

module Vug
  class CacheManager
    def initialize(@config : Config, memory_cache : MemoryCache? = nil)
      @memory_cache = memory_cache
    end

    # Retrieves a cached path for the given URL.
    #
    # Lookup order:
    # 1. Config-backed storage (`on_load` callback) — persistent store
    # 2. In-memory cache — fast ephemeral layer
    def get(url : String) : String?
      # Check config-based storage first
      if cached = @config.load(url)
        return cached
      end

      # Fall back to memory cache
      @memory_cache.try(&.get(url))
    end

    # Stores a URL → path mapping in the memory cache layer only.
    #
    # **Note:** This method does *not* invoke the `on_save` config callback.
    # Persistence is handled earlier in the pipeline by
    # `ImageProcessor::Default#process_bytes`, which calls `@config.save`
    # before storing the result in the cache. This design avoids double-save
    # when the image processor has already persisted the data.
    #
    # If you need to trigger persistence, call `@config.save` explicitly
    # or route through the full `Fetcher` pipeline.
    def set(url : String, local_path : String) : Nil
      # Only store absolute paths in memory cache
      return unless local_path.starts_with?("/")

      # Store in memory cache if available
      @memory_cache.try(&.set(url, local_path))
    end
  end
end
