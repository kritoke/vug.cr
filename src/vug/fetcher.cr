require "http/client"
require "uri"
require "time"
require "./config"
require "./url_validator"
require "./image_validator"
require "./types"
require "./redirect_validator"

module Vug
  class Fetcher
    def initialize(@config : Config = Config.new, cache : MemoryCache? = nil, http_client_factory : HttpClientFactory? = nil, cache_manager : CacheManager? = nil, redirect_validator : RedirectValidator? = nil)
      @http_client_factory = http_client_factory || HttpClientFactory.new(@config)
      @cache_manager = cache_manager || CacheManager.new(@config, cache)
      @redirect_validator = redirect_validator || RedirectValidator.new(@config)
    end

    def fetch(url : String) : Result
      unless UrlValidator.valid_url?(url)
        @config.debug("Invalid or dangerous URL blocked: #{url}")
        return Vug.failure("Invalid URL", url)
      end

      @config.debug("Fetching favicon: #{url}")

      current_url = url
      redirects = 0
      start_time = Time.monotonic
      gray_placeholder_attempts = 0
      max_gray_attempts = 3 # Prevent infinite loops

      loop do
        if (Time.monotonic - start_time).total_seconds > @config.timeout.total_seconds
          @config.warning("fetch(#{url}) timeout after #{@config.timeout.total_seconds}s")
          return Vug.failure("Timeout", url)
        end

        if redirects > @config.max_redirects
          @config.debug("Too many redirects (#{redirects}) for favicon: #{url}")
          return Vug.failure("Too many redirects", url)
        end

        if gray_placeholder_attempts >= max_gray_attempts
          @config.debug("Too many gray placeholder attempts (#{gray_placeholder_attempts}) for favicon: #{url}")
          return Vug.failure("Too many gray placeholder attempts", url)
        end

        if cached = @cache_manager.get(current_url)
          @config.debug("Favicon cache hit: #{current_url}")
          return Vug.success(current_url, cached)
        end

        @config.debug("Fetching favicon from: #{current_url}")

        result = fetch_single(current_url)

        if result.redirect?
          if new_url = result.url
            current_url = new_url
            redirects += 1
            next
          end
          return result
        elsif result.success?
          # Check if this is a gray placeholder that needs fallback
          if should_handle_gray_placeholder?(current_url, result.bytes)
            gray_placeholder_attempts += 1

            # Check if we already have a cached larger version for Google URLs
            if current_url.includes?("google.com/s2/favicons")
              larger_url = current_url.gsub(/sz=\d+/, "sz=256")
              if cached = @cache_manager.get(larger_url)
                @cache_manager.set(current_url, cached)
                return Vug.success(current_url, cached)
              end
            end

            if new_url = get_gray_placeholder_fallback_url(current_url)
              current_url = new_url
              next
            else
              return result
            end
          else
            return result
          end
        else
          return result
        end
      end
    end

    private def fetch_single(url : String) : Result
      uri = URI.parse(url)
      client = @http_client_factory.create_client(uri)

      headers = HTTP::Headers{
        "User-Agent"      => @config.user_agent,
        "Accept-Language" => @config.accept_language,
        "Connection"      => "keep-alive",
      }

      client.get(uri.request_target, headers: headers) do |response|
        if response.status.redirection? && (location = response.headers["Location"]?)
          new_url = uri.resolve(location).to_s
          @config.debug("Favicon redirect: #{new_url}")

          # Validate redirect URL for SSRF protection
          unless @redirect_validator.validate_redirect_url(url, new_url)
            @config.debug("Dangerous redirect blocked: #{new_url}")
            return Vug.failure("Invalid redirect", url)
          end

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
      error_msg = case ex
                  when IO::TimeoutError
                    "Request timed out"
                  when Socket::Addrinfo::Error
                    "DNS resolution failed"
                  else
                    ex.message || "Unknown error"
                  end
      @config.error("fetch_single(#{url})", error_msg)
      Vug.failure(error_msg, url)
    end

    private def handle_success(url : String, data : Bytes, content_type : String) : Result
      if data.size == 0
        @config.debug("Empty favicon response: #{url}")
        return Vug.failure("Empty response", url)
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
        @cache_manager.set(url, saved_path)
        Vug.success(url, saved_path, content_type, data)
      else
        @config.debug("Favicon save failed: #{url}")
        Vug.failure("Save failed", url)
      end
    end

    private def should_handle_gray_placeholder?(url : String, data : Bytes?) : Bool
      return false if data.nil?
      data.size == @config.gray_placeholder_size
    end

    private def get_gray_placeholder_fallback_url(current_url : String) : String?
      if current_url.includes?("google.com/s2/favicons")
        larger_url = current_url.gsub(/sz=\d+/, "sz=256")
        larger_url
      else
        @config.debug("Gray placeholder from non-Google source, trying Google fallback")
        begin
          if host = URI.parse(current_url).host
            google_url = "https://www.google.com/s2/favicons?domain=#{host}&sz=256"
            @config.debug("Google fallback URL: #{google_url}")
            google_url
          else
            nil
          end
        rescue ex
          @config.error("gray placeholder fallback(#{current_url})", ex.message || "Unknown error")
          nil
        end
      end
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

    def self.google_favicon_url(domain : String) : String
      host = UrlProcessor.extract_host_from_url(domain) || domain
      "https://www.google.com/s2/favicons?domain=#{host}&sz=256"
    end
  end
end
