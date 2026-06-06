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
require "./single_request"

module Vug
  class Fetcher
    # Backward-compatible alias — canonical value lives in GrayPlaceholderHandler.
    DDG_DEFAULT_ICON_SIZE = GrayPlaceholderHandler::DDG_DEFAULT_ICON_SIZE

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
      @single_request = SingleRequest.new(@config, @http_client_factory, @image_processor, @redirect_validator, @rate_limiter, @semaphore)
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
        result = @single_request.execute(state.current_url, uri, state.initial_dns_ips, state.redirects)
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
    # Returns nil if the redirect URL cannot be parsed — the caller must
    # handle this gracefully (e.g. by letting the next iteration fail).
    private def handle_redirect_action(new_url : String, initial_dns_ips : Hash(String, Array(String))) : URI?
      new_uri = parse_uri_safe(new_url)
      unless new_uri
        @config.warning("Redirect target could not be parsed: #{new_url}")
        return nil
      end
      if (new_host = new_uri.hostname)
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

    # Parse a URI, returning nil on failure instead of raising.
    # Logs the failure at debug level to aid troubleshooting.
    private def parse_uri_safe(url : String) : URI?
      URI.parse(url)
    rescue ex : URI::Error
      @config.debug("URI parse failed for #{url}: #{ex.message}")
      nil
    end
  end
end
