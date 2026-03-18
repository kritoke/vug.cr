require "uri"
require "./config"
require "./types"
require "./fetcher"

module Vug
  class GrayPlaceholderHandler
    def initialize(@config : Config, @fetcher : Fetcher)
    end

    def handle_gray_placeholder(url : String, data : Bytes) : Result?
      return unless data.size == @config.gray_placeholder_size

      @config.debug("Gray placeholder detected (#{data.size} bytes) for #{url}")

      if url.includes?("google.com/s2/favicons")
        larger_url = url.gsub(/sz=\d+/, "sz=256")
        if cached = @fetcher.load_cached(larger_url)
          return Vug.success(larger_url, cached)
        end
        return @fetcher.fetch(larger_url)
      else
        @config.debug("Gray placeholder from non-Google source, trying Google fallback")
        begin
          if host = URI.parse(url).host
            google_url = "https://www.google.com/s2/favicons?domain=#{host}&sz=256"
            @config.debug("Google fallback URL: #{google_url}")
            result = @fetcher.fetch(google_url)
            if result.local_path
              return result
            end
          end
        rescue ex
          @config.error("gray placeholder fallback(#{url})", ex.message || "Unknown error")
        end
      end

      nil
    end
  end
end
