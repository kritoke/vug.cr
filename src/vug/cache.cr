require "time"
require "mutex"

module Vug
  class MemoryCache
    def initialize(
      @size_limit : Int32 = 10 * 1024 * 1024,
      @entry_ttl : Time::Span = 7.days,
    )
      @cache = Hash(String, {String, Time, Int32}).new
      @current_size = 0
      @mutex = Mutex.new
    end

    def get(url : String) : String?
      @mutex.synchronize do
        if entry = @cache[url]?
          path, timestamp, _size = entry
          if Time.local - timestamp < @entry_ttl
            path
          else
            _, _, file_size = @cache[url]
            @current_size -= file_size
            @cache.delete(url)
            nil
          end
        end
      end
    end

    def set(url : String, local_path : String) : Nil
      return unless local_path.starts_with?("/")

      @mutex.synchronize do
        if existing_entry = @cache[url]?
          _, _, existing_size = existing_entry
          @current_size -= existing_size
        end

        # Get actual file size, fallback to path length if file doesn't exist
        begin
          new_size = File.size(local_path).to_i32
        rescue
          new_size = local_path.bytesize
        end

        while @current_size + new_size > @size_limit && !@cache.empty?
          oldest = @cache.min_by(&.[1][1]).[0]
          _, _, old_size = @cache[oldest]
          @cache.delete(oldest)
          @current_size -= old_size
        end

        @cache[url] = {local_path, Time.local, new_size}
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
