require "http/client"
require "uri"
require "time"
require "./config"
require "./url_validator"
require "./image_validator"
require "./image_processor"
require "./cache_coordinator"
require "./dns_revalidator"
require "./redirect_handler"
require "./redirect_handler_default"
require "./types"
require "./diagnostics"
require "./rate_limiter"
require "./semaphore"
require "./gray_placeholder_handler"

module Vug
  class Fetcher
    # Type-safe action enum replacing bare Symbol dispatch.
    enum Action
      Redirect
      TryFallback
      ReturnResult
      UseCached
    end

    # Mutable state threaded through the fetch loop, replacing scattered
    # local variables and positional tuple returns.
    class LoopState
      property current_url : String
      property current_uri : URI?
      property redirects : Int32 = 0
      property gray_placeholder_attempts : Int32 = 0
      getter visited_urls : Set(String)
      getter initial_dns_ips : Hash(String, Array(String))
      getter start_time : Time::Span
      getter initial_url : String

      MAX_GRAY_ATTEMPTS = 3

      def initialize(@initial_url : String, @start_time : Time::Span)
        @current_url = @initial_url
        @current_uri = URI.parse(@initial_url) rescue nil
        @visited_urls = Set(String).new
        @initial_dns_ips = {} of String => Array(String)
      end
    end
    def initialize(@config : Config = Config.default, cache : MemoryCache? = nil, http_client_factory : HttpClientFactory? = nil, cache_manager : CacheManager? = nil, redirect_validator : RedirectHandler? = nil, cache_coordinator : CacheCoordinator? = nil, image_processor : ImageProcessor? = nil, rate_limiter : RateLimiter? = nil)
      @http_client_factory = http_client_factory || HttpClientFactory.new(@config)
      @cache_manager = cache_manager || CacheManager.new(@config, cache)
      @redirect_validator = redirect_validator || RedirectHandler::Default.new(@config)
      # Coordinator wraps config-backed cache manager and optional memory cache
      @cache_coordinator = cache_coordinator || CacheCoordinator.new(@config, cache, @cache_manager)
      # Image processor may use cache manager for storing saved paths
      @image_processor = image_processor || ImageProcessor::Default.new(@config, @cache_manager)
      @semaphore = Vug.shared_semaphore(@config.max_concurrent_requests)
      @rate_limiter = rate_limiter || RateLimiter.new
      @gray_placeholder_handler = GrayPlaceholderHandler.new(@config, @cache_coordinator)
    end

    def fetch(url : String) : Result
      unless UrlValidator.valid_url?(url)
        @config.debug("Invalid or dangerous URL blocked: #{url}")
        return Vug.failure("Invalid URL", url, error_type: :invalid_url)
      end

      @config.debug("Fetching favicon: #{url}")
      fetch_loop(LoopState.new(url, Time.monotonic))
    end

    private def fetch_loop(state : LoopState) : Result
      loop do
        if termination = check_termination(state)
          return termination
        end

        if path = cached_path_for(state.current_url)
          @config.debug("Favicon cache hit: #{state.current_url}")
          return Vug.success(state.current_url, path)
        end

        # Resolve DNS for the current host (deferred until after cache check
        # to avoid wasted DNS lookups on cache hits)
        state.current_uri = parse_uri_safe(state.current_url)
        parsed = state.current_uri
        if parsed && (host = parsed.hostname)
          state.initial_dns_ips[host] ||= DnsCache.resolve(host)
        end

        # Check for redirect loop (visiting same URL twice in the chain)
        if state.visited_urls.includes?(state.current_url)
          @config.debug("Redirect loop detected: #{state.current_url} already visited")
          return Vug.failure("Redirect loop detected", state.current_url, error_type: :too_many_redirects)
        end
        state.visited_urls.add(state.current_url)

        @config.debug("Fetching favicon from: #{state.current_url}")

        # Reuse parsed URI if available, only parse if we have a redirect URL
        uri = state.current_uri || parse_uri_safe(state.current_url)
        result = fetch_single(state.current_url, uri, state.initial_dns_ips, state.redirects)
        action, next_url, state.current_uri = fetch_result_uri(state.current_url, result, state.current_uri)

        case action
        when .redirect?, .try_fallback?
          handle_result_action(action, next_url, state)
          next if action.redirect? || (action.try_fallback? && next_url)
          return result if action.try_fallback?
        when .return_result?, .use_cached?
          return Vug.success(state.current_url, next_url) if action.use_cached? && next_url
          return result
        end
      end
    end

    private def check_termination(state : LoopState) : Result?
      return Vug.failure("Timeout", state.initial_url, error_type: :timeout) if timed_out?(state.start_time)
      return Vug.failure("Too many redirects", state.initial_url, error_type: :too_many_redirects) if state.redirects > @config.max_redirects
      return Vug.failure("Too many gray placeholder attempts", state.initial_url, error_type: :too_many_gray_placeholder_attempts) if state.gray_placeholder_attempts >= LoopState::MAX_GRAY_ATTEMPTS
      nil
    end

    private def handle_result_action(action : Action, next_url : String?, state : LoopState) : Nil
      case action
      when .redirect?
        if next_url
          state.current_uri = handle_redirect_action(next_url, state.initial_dns_ips)
          state.current_url = next_url
        end
        state.redirects += 1
      when .try_fallback?
        state.gray_placeholder_attempts += 1
        if next_url
          state.current_url = next_url
          state.current_uri = nil # Will be parsed on next iteration
        end
      else
        # ReturnResult / UseCached are handled by the caller
      end
    end

    private def cached_path_for(url : String) : String?
      @cache_coordinator.try(&.fetch(url))
    end

    # Update DNS cache for a redirect target host. Returns the parsed URI.
    private def handle_redirect_action(new_url : String, initial_dns_ips : Hash(String, Array(String))) : URI?
      new_uri = parse_uri_safe(new_url)
      if new_uri && (new_host = new_uri.hostname)
        initial_dns_ips[new_host] ||= DnsCache.resolve(new_host)
      end
      new_uri
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

    private def fetch_result_uri(current_url : String, result : Result, current_uri : URI?) : {Action, String?, URI?}
      if result.redirect?
        return {Action::Redirect, result.url, current_uri}
      end

      if result.success?
        return gray_placeholder_uri(current_url, result, current_uri)
      end

      {Action::ReturnResult, nil, current_uri}
    end

    private def gray_placeholder_uri(current_url : String, result : Result, current_uri : URI?) : {Action, String?, URI?}
      return {Action::ReturnResult, nil, current_uri} unless @gray_placeholder_handler.gray_placeholder?(current_url, result.bytes)

      if cached = @gray_placeholder_handler.cached_larger_version(current_url)
        @gray_placeholder_handler.store_larger_version(current_url, cached)
        return {Action::UseCached, cached, current_uri}
      end

      next_url = @gray_placeholder_handler.fallback_url(current_url)
      {Action::TryFallback, next_url, nil}
    end

    private def fetch_single(url : String, uri : URI?, initial_dns_ips : Hash(String, Array(String)), redirect_count : Int32) : Result
      acquired = acquire_semaphore(url)
      return Vug.failure("Semaphore acquire failed", url, error_type: :fetch_error) unless acquired
      begin
        parsed_uri = uri || parse_uri(url)
        host = parsed_uri.hostname
        check_rate_and_dns(url, host, initial_dns_ips, redirect_count, parsed_uri)
      rescue ex : URI::Error
        @config.error("fetch_single(#{url})", "Invalid URL format: #{ex.message}")
        Vug.failure("Invalid URL", url, error_type: :invalid_url)
      rescue ex : Socket::Addrinfo::Error
        @config.error("fetch_single(#{url})", format_exception(ex, "DNS resolution failed"))
        Vug.failure("DNS resolution failed", url, error_type: :fetch_error)
      rescue ex : OpenSSL::SSL::Error
        @config.error("fetch_single(#{url})", format_exception(ex, "SSL error"))
        Vug.failure("SSL error", url, error_type: :fetch_error)
      rescue ex : IO::TimeoutError
        @config.warning("fetch_single(#{url}): #{ex.message}")
        Vug.failure("Read timed out", url, error_type: :fetch_error)
      rescue ex : IO::Error | Socket::Error
        @config.error("fetch_single(#{url})", format_exception(ex))
        Vug.failure(ex.message || "Unknown error", url, error_type: :fetch_error)
      ensure
        @semaphore.release if acquired
      end
    end

    private def acquire_semaphore(url : String) : Bool
      acquired = @semaphore.acquire
      unless acquired
        @config.error("fetch_single(#{url})", "Semaphore acquire timed out")
      end
      acquired
    rescue ex : Channel::ClosedError
      @config.error("fetch_single(#{url})", "Semaphore channel closed: #{ex.message}")
      false
    end

    # Parse a URI, returning nil on failure instead of raising.
    # Logs the failure at debug level to aid troubleshooting.
    private def parse_uri_safe(url : String) : URI?
      URI.parse(url)
    rescue ex : URI::Error
      @config.debug("URI parse failed for #{url}: #{ex.message}")
      nil
    end

    private def parse_uri(url : String) : URI
      URI.parse(url)
    rescue ex : URI::Error
      @config.error("fetch_single(#{url})", "Invalid URL format: #{ex.message}")
      raise ex
    end

    private def handle_redirect(url : String, uri : URI, response : HTTP::Client::Response, redirect_count : Int32) : Result?
      return unless response.status.redirection? && (location = response.headers["Location"]?)

      new_url = uri.resolve(location).to_s
      case action = @redirect_validator.decide(url, new_url, redirect_count)
      when FetchAction::Follow
        @config.debug("Favicon redirect: #{action.location}")
        Vug.redirect(action.location)
      when FetchAction::Deny
        @config.debug("Dangerous redirect blocked: #{new_url} (#{action.reason})")
        Vug.failure("Invalid redirect", url, error_type: :invalid_redirect)
      end
    end

    private def revalidate_dns_for?(url : String, host : String?, initial_dns_ips : Hash(String, Array(String))) : Bool
      return false if host.nil? || host.empty?

      current_ips = DnsCache.resolve(host)
      if current_ips.empty?
        @config.debug("revalidate_dns_for?(#{url}): DNS resolution returned no result")
        return false
      end

      if current_ips.any? { |ip| UrlValidator.private_ip?(ip) }
        @config.error("revalidate_dns_for?(#{url})", "Blocked: resolved to private IP at connection time")
        return false
      end

      if initial_ips = initial_dns_ips[host]?
        if DNSRevalidator.should_revalidate?(initial_ips, current_ips)
          @config.error("revalidate_dns_for?(#{url})", "Blocked: DNS changed from #{initial_ips} to #{current_ips} (possible rebinding)")
          return false
        end
      end

      true
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
      Diagnostics.format_exception(ex, prefix)
    end

    private def check_rate_and_dns(url : String, host : String?, initial_dns_ips : Hash(String, Array(String)), redirect_count : Int32, uri : URI) : Result
      if host && !@rate_limiter.allow?(host)
        @config.debug("Rate limited: #{host} exceeded #{@rate_limiter.max_per_minute} requests/minute")
        return Vug.failure("Rate limited", url, error_type: :rate_limited)
      end

      unless revalidate_dns_for?(url, host, initial_dns_ips)
        return Vug.failure("DNS revalidation failed", url, error_type: :dns_revalidation_failed)
      end

      perform_http_request(url, uri, redirect_count)
    end

    private def perform_http_request(url : String, uri : URI, redirect_count : Int32) : Result
      client = @http_client_factory.create_client(uri)

      headers = HTTP::Headers{
        "User-Agent"      => @config.user_agent,
        "Accept-Language" => @config.accept_language,
        "Connection"      => "keep-alive",
      }

      result : Result? = nil
      begin
        client.get(uri.request_target, headers: headers) do |response|
          result = handle_redirect(url, uri, response, redirect_count) if response.status.redirection?
          result ||= process_response(url, response) if response.status.success?
          result ||= handle_error(url, response.status_code)
        end
      rescue ex : Exception
        # Close the client on any exception to avoid reusing corrupted connections
        @http_client_factory.release_client(uri, client, success: false)
        raise ex
      else
        # Only pool successful requests
        @http_client_factory.release_client(uri, client, success: true)
      end
      result || Vug.failure("Unexpected HTTP error", url.to_s)
    end

    private def process_response(url : String, response : HTTP::Client::Response) : Result
      content_type = response.content_type || "image/png"
      memory = IO::Memory.new
      IO.copy(response.body_io, memory, limit: @config.max_size)
      @image_processor.process_bytes(url, memory.to_slice, content_type)
    end
  end
end
