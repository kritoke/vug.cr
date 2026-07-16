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
require "./loop_state"
require "./loop_action"
require "./fetch_decision"
require "./fetch_errors"
require "./single_request"

module Vug
  class Fetcher
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

        prepare_request(state)

        @config.debug("Fetching favicon from: #{state.current_url}")

        uri = state.current_uri || UrlValidator.parse_or_nil(state.current_url)
        result = @single_request.execute(state.current_url, uri, state.initial_dns_ips, state.redirects)
        decision = fetch_decision(state.current_url, result)
        state.current_uri = nil if decision.reparse

        if outcome = apply_action(decision, result, state)
          return outcome
        end
      end
    rescue ex : RedirectLoopError
      Vug.failure("Redirect loop detected", ex.url, error_type: :too_many_redirects)
    end

    # Apply the action from a fetch result. Returns a Result to return
    # immediately, or nil to continue the loop.
    private def apply_action(decision : FetchDecision, result : Result, state : LoopState) : Result?
      case decision.action
      when .redirect?
        handle_result_action(decision, state)
        # Fail fast if the redirect URL could not be parsed — don't spin
        # the loop until timeout on an unparseable redirect target.
        if state.current_uri.nil? && decision.next_url
          return Vug.failure("Invalid redirect URL", state.current_url, error_type: :invalid_redirect)
        end
        nil
      when .try_fallback?
        handle_result_action(decision, state)
        # Continue if we have a fallback URL to try; otherwise return the
        # gray-placeholder result that triggered the decision.
        decision.next_url ? nil : result
      when .return_result?
        result
      when .use_cached?
        if next_url = decision.next_url
          Vug.success(state.current_url, next_url)
        else
          # Defensive: in the current dispatch UseCached always carries
          # a next_url, but if a future caller passes nil we fall back
          # to the result rather than raising.
          result
        end
      end
    end

    # Resolve DNS and check for redirect loops before making a request.
    private def prepare_request(state : LoopState) : Nil
      state.current_uri = UrlValidator.parse_or_nil(state.current_url)
      if state.current_uri.nil?
        @config.debug("URI parse failed for #{state.current_url}")
      end
      if host = state.current_uri.try(&.hostname)
        state.initial_dns_ips[host] ||= DnsCache.resolve(host)
      end

      if state.visited_urls.includes?(state.current_url)
        @config.debug("Redirect loop detected: #{state.current_url} already visited")
        raise RedirectLoopError.new(state.current_url)
      end
      state.visited_urls.add(state.current_url)
    end

    private def check_termination(state : LoopState) : Result?
      return Vug.failure("Timeout", state.initial_url, error_type: :timeout) if timed_out?(state.start_time)
      return Vug.failure("Too many redirects", state.initial_url, error_type: :too_many_redirects) if state.redirects > @config.max_redirects
      return Vug.failure("Too many gray placeholder attempts", state.initial_url, error_type: :too_many_gray_placeholder_attempts) if state.gray_placeholder_attempts >= GrayPlaceholderHandler::MAX_FALLBACK_ATTEMPTS
      nil
    end

    private def handle_result_action(decision : FetchDecision, state : LoopState) : Nil
      case decision.action
      when .redirect?
        if next_url = decision.next_url
          state.current_uri = handle_redirect_action(next_url, state.initial_dns_ips)
          state.current_url = next_url
        end
        state.redirects += 1
      when .try_fallback?
        state.gray_placeholder_attempts += 1
        if next_url = decision.next_url
          state.current_url = next_url
          # current_uri is already nil because the call site set
          # state.current_uri = nil when decision.reparse was true.
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
      new_uri = UrlValidator.parse_or_nil(new_url)
      unless new_uri
        @config.warning("Redirect target could not be parsed: #{new_url}")
        return
      end
      if new_host = new_uri.hostname
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

    private def fetch_decision(current_url : String, result : Result) : FetchDecision
      if result.redirect?
        return FetchDecision.new(LoopAction::Redirect, result.url, reparse: false)
      end

      return gray_placeholder_decision(current_url, result) if result.success?

      FetchDecision.new(LoopAction::ReturnResult, nil, reparse: false)
    end

    private def gray_placeholder_decision(current_url : String, result : Result) : FetchDecision
      return FetchDecision.new(LoopAction::ReturnResult, nil, reparse: false) unless @gray_placeholder_handler.gray_placeholder?(current_url, result.bytes)

      if cached = @gray_placeholder_handler.cached_larger_version(current_url)
        @gray_placeholder_handler.store_larger_version(current_url, cached)
        return FetchDecision.new(LoopAction::UseCached, cached, reparse: false)
      end

      next_url = @gray_placeholder_handler.fallback_url(current_url)
      FetchDecision.new(LoopAction::TryFallback, next_url, reparse: true)
    end
  end
end
