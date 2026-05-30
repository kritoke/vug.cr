module Vug
  class CacheCoordinator
    def initialize(config : Config, memory_cache : MemoryCache? = nil, cache_manager : CacheManager? = nil)
      @config = config
      @memory_cache = memory_cache
      @cache_manager = cache_manager
    end

    def fetch_from_cache(url : String) : String?
      if path = @cache_manager.try(&.get(url))
        return path
      end

      @memory_cache.try(&.get(url))
    end

    # Stores a fetched result in both the memory cache and config-backed cache manager.
    #
    # **Note:** Neither layer invokes the `on_save` config callback through this path.
    # The `on_save` callback is called by `ImageProcessor::Default#process_bytes` before
    # this method is reached. This avoids double-persisting the same data.
    # See `CacheManager#set` for details on the write-path asymmetry.
    def store_to_cache(url : String, path : String) : Nil
      @memory_cache.try(&.set(url, path))
      @cache_manager.try(&.set(url, path))
    end

    def fetch(url : String) : String?
      fetch_from_cache(url)
    end

    def store(url : String, path : String) : Nil
      store_to_cache(url, path)
    end
  end
end
