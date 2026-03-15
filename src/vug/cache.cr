require "time"
require "mutex"

module Vug
  class MemoryCache
    def initialize(
      @size_limit : Int32 = 10 * 1024 * 1024,
      @entry_ttl : Time::Span = 7.days,
    )
      @cache = Hash(String, {String, Time}).new
      @current_size = 0
      @mutex = Mutex.new
    end

    def get(url : String) : String?
      @mutex.synchronize do
        if entry = @cache[url]?
          data, timestamp = entry
          if Time.local - timestamp < @entry_ttl
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
        new_size = local_path.bytesize

        while @current_size + new_size > @size_limit && !@cache.empty?
          oldest = @cache.min_by(&.[1][1]).[0]
          old_path = @cache[oldest]?.try(&.[0]) || ""
          @cache.delete(oldest)
          @current_size -= old_path.bytesize
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
