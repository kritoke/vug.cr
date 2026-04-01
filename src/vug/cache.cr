require "time"
require "mutex"
require "deque"

module Vug
  record CacheEntry, path : String, timestamp : Time::Span, size : Int32

  class MemoryCache
    def initialize(
      @size_limit : Int32 = 10 * 1024 * 1024,
      @entry_ttl : Time::Span = 7.days,
    )
      @cache = Hash(String, CacheEntry).new
      @insertion_order = Deque(String).new
      @current_size = 0
      @mutex = Mutex.new
    end

    def get(url : String) : String?
      @mutex.synchronize do
        if entry = @cache[url]?
          if Time.monotonic - entry.timestamp < @entry_ttl
            entry.path
          else
            @current_size -= entry.size
            @cache.delete(url)
            nil
          end
        end
      end
    end

    def set(url : String, local_path : String) : Nil
      return unless local_path.starts_with?("/")

      new_size = begin
        File.size(local_path).to_i32
      rescue File::Error
        local_path.bytesize
      end

      @mutex.synchronize do
        if existing_entry = @cache[url]?
          @current_size -= existing_entry.size
        else
          @insertion_order << url
        end

        while @current_size + new_size > @size_limit && !@cache.empty?
          oldest_key = @insertion_order.shift?
          break unless oldest_key

          if entry = @cache[oldest_key]?
            @current_size -= entry.size
            @cache.delete(oldest_key)
          end
        end

        @cache[url] = CacheEntry.new(local_path, Time.monotonic, new_size)
        @current_size += new_size
      end
    end

    def clear : Nil
      @mutex.synchronize do
        @cache.clear
        @insertion_order.clear
        @current_size = 0
      end
    end

    def size : Int32
      @mutex.synchronize { @cache.size }
    end
  end
end
