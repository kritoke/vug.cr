require "http/client"
require "uri"
require "time"
require "./config"
require "./image_validator"
require "./types"

module Vug
  class Fetcher
    def initialize(@config : Config = Config.new, @cache : MemoryCache? = nil)
    end

    def fetch(url : String) : Result
      @config.debug("Fetching favicon: #{url}")

      current_url = url
      redirects = 0
      start_time = Time.monotonic

      loop do
        if (Time.monotonic - start_time).total_seconds > @config.timeout.total_seconds
          @config.warning("fetch(#{url}) timeout after #{@config.timeout.total_seconds}s")
          return Vug.failure("Timeout", url)
        end

        if redirects > @config.max_redirects
          @config.debug("Too many redirects (#{redirects}) for favicon: #{url}")
          return Vug.failure("Too many redirects", url)
        end

        if cached = load_cached(current_url)
          @config.debug("Favicon cache hit: #{current_url}")
          return Vug.success(current_url, cached)
        end

        @config.debug("Fetching favicon from: #{current_url}")

        result = fetch_single(current_url)

        case result
        in .redirect?
          if new_url = result.url
            current_url = new_url
            redirects += 1
            next
          end
        in .success?
          return result
        in .failure?
          return result
        end
      end
    end

    private def fetch_single(url : String) : Result
      uri = URI.parse(url)
      client = create_client(uri)

      headers = HTTP::Headers{
        "User-Agent"      => @config.user_agent,
        "Accept-Language" => @config.accept_language,
        "Connection"      => "keep-alive",
      }

      begin
        client.get(uri.request_target, headers: headers) do |response|
          if response.status.redirection? && (location = response.headers["Location"]?)
            new_url = uri.resolve(location).to_s
            @config.debug("Favicon redirect: #{new_url}")
            return Result.new(url: new_url, local_path: nil, content_type: nil, bytes: nil, error: nil)
          end

          if response.status.success?
            content_type = response.content_type || "image/png"
            memory = IO::Memory.new
            IO.copy(response.body_io, memory, limit: @config.max_size)

            return handle_success(url, memory.to_slice, content_type)
          else
            return handle_error(url, response.status_code)
          end
        end
      rescue ex
        @config.error("fetch_single(#{url})", ex)
        Vug.failure(ex.message || "Unknown error", url)
      end
    end

    private def handle_success(url : String, data : Bytes, content_type : String) : Result
      if data.size == 0
        @config.debug("Empty favicon response: #{url}")
        return Vug.failure("Empty response", url)
      end

      if gray_result = handle_gray_placeholder(url, data)
        return gray_result
      end

      unless ImageValidator.valid?(data)
        @config.debug("Invalid favicon content (not an image): #{url}")
        return Vug.failure("Invalid image", url)
      end

      # Get actual image dimensions if available
      dimensions_info = ""
      if dims = ImageValidator.get_image_dimensions(data)
        width, height = dims
        dimensions_info = " (#{width}x#{height})"
      end

      @config.debug("Favicon fetched: #{url}, size=#{data.size}, type=#{content_type}#{dimensions_info}")

      if saved_path = @config.save(url, data, content_type)
        @config.debug("Favicon saved: #{saved_path}")
        @cache.try(&.set(url, saved_path))
        Vug.success(url, saved_path, content_type, data)
      else
        @config.debug("Favicon save failed: #{url}")
        Vug.failure("Save failed", url)
      end
    end

    private def handle_gray_placeholder(url : String, data : Bytes) : Result?
      return unless data.size == @config.gray_placeholder_size

      @config.debug("Gray placeholder detected (#{data.size} bytes) for #{url}")

      if url.includes?("google.com/s2/favicons")
        larger_url = url.gsub(/sz=\d+/, "sz=256")
        if cached = load_cached(larger_url)
          return Vug.success(larger_url, cached)
        end
        return fetch(larger_url)
      else
        @config.debug("Gray placeholder from non-Google source, trying Google fallback")
        begin
          if host = URI.parse(url).host
            google_url = "https://www.google.com/s2/favicons?domain=#{host}&sz=256"
            @config.debug("Google fallback URL: #{google_url}")
            result = fetch(google_url)
            if path = result.local_path
              @cache.try(&.set(google_url, path))
              return result
            end
          end
        rescue ex
          @config.error("gray placeholder fallback(#{url})", ex)
        end
      end

      nil
    end

    private def handle_error(url : String, status_code : Int32) : Result
      case status_code
      when 404
        @config.debug("Favicon 404: #{url}")
      when 403
        @config.debug("Favicon 403: #{url}")
      else
        @config.debug("Favicon error #{status_code}: #{url}")
      end
      Vug.failure("HTTP #{status_code}", url)
    end

    private def load_cached(url : String) : String?
      if cached = @cache.try(&.get(url))
        return cached
      end
      @config.load(url)
    end

    private def create_client(uri : URI) : HTTP::Client
      client = HTTP::Client.new(uri)
      client.compress = true
      client.read_timeout = @config.timeout
      client.connect_timeout = @config.connect_timeout
      client
    end

    def self.google_favicon_url(domain : String) : String
      host = domain.gsub(/\/feed\/?$/, "")
      if host.starts_with?("http")
        parsed = URI.parse(host)
        host = parsed.host || host
      end
      "https://www.google.com/s2/favicons?domain=#{host}&sz=256"
    end
  end
end
