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
