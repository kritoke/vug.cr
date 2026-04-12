require "http/client"
require "uri"
require "time"
require "./config"
require "./url_validator"
require "./image_validator"
require "./image_processor"
require "./cache_coordinator"
require "./types"
require "./redirect_validator"

module Vug
  class Fetcher
    def initialize(@config : Config = Config.default, cache : MemoryCache? = nil, http_client_factory : HttpClientFactory? = nil, cache_manager : CacheManager? = nil, redirect_validator : RedirectValidator? = nil, cache_coordinator : CacheCoordinator? = nil, image_processor : ImageProcessor? = nil)
      @http_client_factory = http_client_factory || HttpClientFactory.new(@config)
      @cache_manager = cache_manager || CacheManager.new(@config, cache)
      @redirect_validator = redirect_validator || RedirectValidator.new(@config)
      # Coordinator wraps config-backed cache manager and optional memory cache
      @cache_coordinator = cache_coordinator || CacheCoordinator.new(@config, cache, @cache_manager)
      # Image processor may use cache manager for storing saved paths
      @image_processor = image_processor || ImageProcessor::Default.new(@config, @cache_manager)
      @semaphore = Vug.shared_semaphore(@config.max_concurrent_requests)
    end

    def fetch(url : String) : Result
      unless UrlValidator.valid_url?(url)
        @config.debug("Invalid or dangerous URL blocked: #{url}")
        return Vug.failure("Invalid URL", url, error_type: :invalid_url)
      end

      @config.debug("Fetching favicon: #{url}")

      # Initialize loop state and delegate loop work to fetch_loop to reduce
      # cyclomatic complexity measured by linters.
      current_url = url
      start_time = Time.monotonic
      initial_dns_ips = {} of String => Array(String)

      uri = URI.parse(url) rescue nil
      if uri && (host = uri.hostname)
        initial_dns_ips[host] ||= DnsCache.resolve(host)
      end

      fetch_loop(current_url, start_time, initial_dns_ips)
    end

    private def fetch_loop(initial_url : String, start_time : Time::Span, initial_dns_ips : Hash(String, Array(String))) : Result
      current_url = initial_url
      redirects = 0
      gray_placeholder_attempts = 0
      max_gray_attempts = 3

      loop do
        return Vug.failure("Timeout", initial_url, error_type: :timeout) if timed_out?(start_time)
        # Enforce redirect limit: block when redirects reached the configured maximum
        return Vug.failure("Too many redirects", initial_url, error_type: :too_many_redirects) if redirects >= @config.max_redirects
        return Vug.failure("Too many gray placeholder attempts", initial_url, error_type: :too_many_gray_placeholder_attempts) if gray_placeholder_attempts >= max_gray_attempts

        # Check coordinated cache first (which favors config-backed storage), then fall back
        if path = cached_path_for(current_url)
          @config.debug("Favicon cache hit: #{current_url}")
          return Vug.success(current_url, path)
        end

        @config.debug("Fetching favicon from: #{current_url}")

        result = fetch_single(current_url, initial_dns_ips)
        action, next_url = handle_fetch_result(current_url, result, gray_placeholder_attempts)

        case action
        when :redirect
          if next_url
            handle_redirect_action(next_url, initial_dns_ips)
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
        when :use_cached
          if next_url
            return Vug.success(current_url, next_url)
          end
          return result
        end
      end
    end

    # Return cached path from coord or manager, or nil
    private def cached_path_for(url : String) : String?
      @cache_coordinator.try(&.fetch_from_cache(url)) || @cache_manager.get(url)
    end

    # Update DNS cache for a redirect target host. This is isolated to
    # reduce complexity in the main loop.
    private def handle_redirect_action(new_url : String, initial_dns_ips : Hash(String, Array(String)))
      new_uri = URI.parse(new_url) rescue nil
      if new_uri && (new_host = new_uri.hostname)
        initial_dns_ips[new_host] ||= DnsCache.resolve(new_host)
      end
    end

    private def timed_out?(start_time : Time::Span) : Bool
      # Use monotonic time to avoid issues with system clock changes. A
      # negative elapsed value can indicate wrap/overflow on some platforms
      # or anomalies; treat negative elapsed as an immediate timeout to be
      # defensive about long-running requests.
      elapsed = Time.monotonic - start_time
      return true if elapsed < 0.seconds
      elapsed > @config.timeout
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
        if cached = @cache_coordinator.try(&.fetch_from_cache(larger_url)) || @cache_manager.get(larger_url)
          @cache_coordinator.try(&.store_to_cache(current_url, cached)) || @cache_manager.set(current_url, cached)
          return {:use_cached, cached}
        end
      end

      next_url = get_gray_placeholder_fallback_url(current_url)
      {:try_fallback, next_url}
    end

    private def fetch_single(url : String, initial_dns_ips : Hash(String, Array(String))) : Result
      @semaphore.acquire
      begin
        uri = URI.parse(url)
        unless revalidate_dns_for?(url, uri.hostname, initial_dns_ips)
          return Vug.failure("DNS revalidation failed", url, error_type: :dns_revalidation_failed)
        end

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

            # Use injected ImageProcessor to validate and save image bytes
            return @image_processor.process_bytes(url, memory.to_slice, content_type)
          else
            return handle_error(url, response.status_code)
          end
        end
      rescue ex : IO::TimeoutError
        @config.error("fetch_single(#{url})", format_exception(ex, "Request timed out"))
        Vug.failure("Request timed out", url, error_type: :fetch_error)
      rescue ex : Socket::Addrinfo::Error
        @config.error("fetch_single(#{url})", format_exception(ex, "DNS resolution failed"))
        Vug.failure("DNS resolution failed", url, error_type: :fetch_error)
      rescue ex : IO::Error | Socket::Error | URI::Error
        @config.error("fetch_single(#{url})", format_exception(ex))
        Vug.failure(ex.message || "Unknown error", url, error_type: :fetch_error)
      ensure
        @semaphore.release
      end
    end

    private def revalidate_dns_for?(url : String, host : String?, initial_dns_ips : Hash(String, Array(String))) : Bool
      return false if host.nil? || host.empty?

      current_ips = DnsCache.resolve(host)
      if current_ips.empty?
        @config.error("revalidate_dns_for?(#{url})", "Blocked: DNS resolution returned no result at connection time")
        return false
      end

      if current_ips.any? { |ip| UrlValidator.private_ip?(ip) }
        @config.error("revalidate_dns_for?(#{url})", "Blocked: resolved to private IP at connection time")
        return false
      end

      if initial_ips = initial_dns_ips[host]?
        if initial_ips.to_set != current_ips.to_set
          @config.error("revalidate_dns_for?(#{url})", "Blocked: DNS changed from #{initial_ips} to #{current_ips} (possible rebinding)")
          return false
        end
      end

      true
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
        @cache_coordinator.try(&.store_to_cache(url, saved_path)) || @cache_manager.set(url, saved_path)
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

    private def format_exception(ex : Exception, prefix : String? = nil) : String
      message = prefix || ex.message || "Unknown error"
      stack = ex.backtrace.join("\n")
      "#{message} | exception=#{ex.class} | backtrace=\n#{stack}"
    end
  end
end
