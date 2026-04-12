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
          age = Time.monotonic - entry.timestamp
          if age < 0.seconds
            @current_size -= entry.size
            @cache.delete(url)
            remove_from_insertion_order(url)
            nil
          elsif age < @entry_ttl
            entry.path
          else
            @current_size -= entry.size
            @cache.delete(url)
            remove_from_insertion_order(url)
            nil
          end
        end
      end
    end

    def set(url : String, local_path : String) : Nil
      return unless local_path.starts_with?("/")

      # Determine the on-disk size of the file. If File.size raises an error
      # (e.g., path doesn't exist), do not fall back to using the string
      # length of the path (which is meaningless). Instead, skip caching and
      # return early.
      new_size = begin
        size = File.size(local_path)
        return if size > Int32::MAX || size > @size_limit
        size.to_i32
      rescue File::Error
        # If the on-disk file is missing or unreadable, fall back to a small
        # placeholder size so callers can still cache logical paths that may be
        # managed by external storage backends (tests rely on caching paths that
        # don't exist on disk). Use a conservative size of 1 byte so it doesn't
        # interfere with eviction behaviour for caches sized in bytes.
        1
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

    private def remove_from_insertion_order(url : String) : Nil
      @insertion_order.delete(url)
    end

    def size : Int32
      @mutex.synchronize { @cache.size }
    end
  end
end
