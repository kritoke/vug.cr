module Vug
  class CacheCoordinator
    def initialize(config : Config, memory_cache : MemoryCache? = nil, cache_manager : CacheManager? = nil)
      @config = config
      @memory_cache = memory_cache
      @cache_manager = cache_manager
    end

    def fetch_from_cache(url : String) : String?
      # Prefer config-based storage (cache_manager) then memory_cache
      if path = @cache_manager.try(&.get(url))
        return path
      end

      @memory_cache.try(&.get(url))
    end

    def store_to_cache(url : String, path : String) : Nil
      @memory_cache.try(&.set(url, path))
      @cache_manager.try(&.set(url, path))
    end
  end
end
