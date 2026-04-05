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
    def initialize(@config : Config = Config.default, cache : MemoryCache? = nil, http_client_factory : HttpClientFactory? = nil, cache_manager : CacheManager? = nil, redirect_validator : RedirectValidator? = nil)
      @http_client_factory = http_client_factory || HttpClientFactory.new(@config)
      @cache_manager = cache_manager || CacheManager.new(@config, cache)
      @redirect_validator = redirect_validator || RedirectValidator.new(@config)
      @semaphore = Vug.shared_semaphore(@config.max_concurrent_requests)
    end

    def fetch(url : String) : Result
      unless UrlValidator.valid_url?(url)
        @config.debug("Invalid or dangerous URL blocked: #{url}")
        return Vug.failure("Invalid URL", url, error_type: :invalid_url)
      end

      @config.debug("Fetching favicon: #{url}")

      current_url = url
      redirects = 0
      start_time = Time.monotonic
      gray_placeholder_attempts = 0
      max_gray_attempts = 3

      loop do
        return Vug.failure("Timeout", url, error_type: :timeout) if timed_out?(start_time)
        return Vug.failure("Too many redirects", url, error_type: :too_many_redirects) if redirects > @config.max_redirects
        return Vug.failure("Too many gray placeholder attempts", url, error_type: :too_many_gray_placeholder_attempts) if gray_placeholder_attempts >= max_gray_attempts

        if cached = @cache_manager.get(current_url)
          @config.debug("Favicon cache hit: #{current_url}")
          return Vug.success(current_url, cached)
        end

        @config.debug("Fetching favicon from: #{current_url}")

        result = fetch_single(current_url)
        action, next_url = handle_fetch_result(current_url, result, gray_placeholder_attempts)

        case action
        when :redirect
          if next_url
            current_url = next_url
          end
          redirects += 1
          next
        when :try_fallback
          gray_placeholder_attempts += 1
          if next_url
            current_url = next_url
            next
          end
          return result
        when :return_result
          return result
        end
      end
    end

    private def timed_out?(start_time : Time::Span) : Bool
      (Time.monotonic - start_time) > @config.timeout
    end

    private def handle_fetch_result(current_url : String, result : Result, gray_placeholder_attempts : Int32) : {Symbol, String?}
      if result.redirect?
        return {:redirect, result.url}
      end

      if result.success?
        return handle_gray_placeholder(current_url, result)
      end

      {:return_result, nil}
    end

    private def handle_gray_placeholder(current_url : String, result : Result) : {Symbol, String?}
      return {:return_result, nil} unless should_handle_gray_placeholder?(current_url, result.bytes)

      if current_url.includes?("google.com/s2/favicons")
        larger_url = google_larger_url(current_url)
        if cached = @cache_manager.get(larger_url)
          @cache_manager.set(current_url, cached)
          return {:return_result, nil}
        end
      end

      next_url = get_gray_placeholder_fallback_url(current_url)
      {:try_fallback, next_url}
    end

    private def fetch_single(url : String) : Result
      @semaphore.acquire
      begin
        # Re-validate DNS at connection time to prevent DNS rebinding
        unless UrlValidator.revalidate_url?(url)
          @config.debug("DNS revalidation failed (possible rebinding): #{url}")
          return Vug.failure("DNS revalidation failed", url, error_type: :dns_revalidation_failed)
        end

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
              return Vug.failure("Invalid redirect", url, error_type: :invalid_redirect)
            end

            return Vug.redirect(new_url)
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
      rescue ex : IO::Error | Socket::Error | URI::Error
        error_msg = case ex
                    when IO::TimeoutError
                      "Request timed out"
                    when Socket::Addrinfo::Error
                      "DNS resolution failed"
                    else
                      ex.message || "Unknown error"
                    end
        @config.error("fetch_single(#{url})", error_msg)
        Vug.failure(error_msg, url, error_type: :fetch_error)
      ensure
        @semaphore.release
      end
    end

    private def handle_success(url : String, data : Bytes, content_type : String) : Result
      if data.empty?
        @config.debug("Empty favicon response: #{url}")
        return Vug.failure("Empty response", url, error_type: :empty_response)
      end

      unless ImageValidator.valid?(data, @config.image_validation_hard?)
        @config.debug("Invalid favicon content (not an image): #{url}")
        return Vug.failure("Invalid image", url, error_type: :invalid_image)
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
        Vug.failure("Save failed", url, error_type: :save_failed)
      end
    end

    private def should_handle_gray_placeholder?(url : String, data : Bytes?) : Bool
      return false if data.nil?
      data.size == @config.gray_placeholder_size
    end

    private def get_gray_placeholder_fallback_url(current_url : String) : String?
      if current_url.includes?("google.com/s2/favicons")
        google_larger_url(current_url)
      else
        @config.debug("Gray placeholder from non-Google source, trying Google fallback")
        begin
          if host = URI.parse(current_url).host
            encoded_host = URI.encode_www_form(host)
            google_url = "https://www.google.com/s2/favicons?domain=#{encoded_host}&sz=256"
            @config.debug("Google fallback URL: #{google_url}")
            google_url
          end
        rescue ex : URI::Error
          @config.error("gray placeholder fallback(#{current_url})", ex.message || "Unknown error")
        end
      end
    end

    private def google_larger_url(url : String) : String
      url.gsub(/sz=\d+/, "sz=256")
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
      Vug.failure("HTTP #{status_code}", url, error_type: :http_error)
    end
  end
end
