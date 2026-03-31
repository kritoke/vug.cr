require "time"
require "mutex"

module Vug
  class MemoryCache
    def initialize(
      @size_limit : Int32 = 10 * 1024 * 1024,
      @entry_ttl : Time::Span = 7.days,
    )
      # Store {path, monotonic_timestamp, size} where monotonic_timestamp is Time::Span
      @cache = Hash(String, {String, Time::Span, Int32}).new
      @current_size = 0
      @mutex = Mutex.new
    end

    def get(url : String) : String?
      @mutex.synchronize do
        if entry = @cache[url]?
          path, timestamp, _size = entry
          # Check if entry has expired based on elapsed monotonic time
          if Time.monotonic - timestamp < @entry_ttl
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

      new_size = begin
        File.size(local_path).to_i32
      rescue File::Error
        local_path.bytesize
      end

      @mutex.synchronize do
        if existing_entry = @cache[url]?
          _, _, existing_size = existing_entry
          @current_size -= existing_size
        end

        while @current_size + new_size > @size_limit && !@cache.empty?
          oldest_key = nil
          oldest_time = Time::Span::MAX
          oldest_size = 0

          @cache.each do |key, (_, timestamp, size)|
            if timestamp < oldest_time
              oldest_key = key
              oldest_time = timestamp
              oldest_size = size
            end
          end

          if oldest_key
            @cache.delete(oldest_key)
            @current_size -= oldest_size
          end
        end

        @cache[url] = {local_path, Time.monotonic, new_size}
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
