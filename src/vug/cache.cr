require "time"
require "mutex"

module Vug
  class MemoryCache
    CACHE_SIZE_LIMIT = 10 * 1024 * 1024
    ENTRY_TTL        = 7.days

    @cache = Hash(String, {String, Time}).new
    @current_size = 0
    @mutex = Mutex.new

    def get(url : String) : String?
      @mutex.synchronize do
        if entry = @cache[url]?
          data, timestamp = entry
          if Time.local - timestamp < ENTRY_TTL
            data
          else
            @current_size -= 1024
            @cache.delete(url)
            nil
          end
        end
      end
    end

    def set(url : String, local_path : String) : Nil
      return unless local_path.starts_with?("/")

      @mutex.synchronize do
        new_size = 1024

        while @current_size + new_size > CACHE_SIZE_LIMIT && !@cache.empty?
          oldest = @cache.min_by(&.[1][1]).[0]
          @cache.delete(oldest)
          @current_size -= 1024
        end

        @cache[url] = {local_path, Time.local}
        @current_size += new_size
      end
    end

    def clear : Nil
      @mutex.synchronize do
        @cache.clear
        @current_size = 0
      end
    end

    def size : Int32
      @mutex.synchronize { @cache.size }
    end
  end
end
