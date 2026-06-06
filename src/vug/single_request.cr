require "http/client"
require "uri"
require "./config"
require "./url_validator"
require "./image_processor"
require "./dns_revalidator"
require "./redirect_handler"
require "./rate_limiter"
require "./semaphore"
require "./diagnostics"

module Vug
  # Executes a single HTTP request for a favicon URL, handling semaphore
  # acquisition, rate limiting, DNS revalidation, HTTP client lifecycle,
  # redirect detection, and response processing.
  #
  # Extracted from Fetcher to follow Single Responsibility Principle.
  # Fetcher owns the fetch loop; SingleRequest owns one HTTP round-trip.
  class SingleRequest
    def initialize(
      @config : Config,
      @http_client_factory : HttpClientFactory,
      @image_processor : ImageProcessor,
      @redirect_validator : RedirectHandler,
      @rate_limiter : RateLimiter,
      @semaphore : Vug::Semaphore,
    )
    end

    # Execute a single HTTP request for the given URL.
    # Handles semaphore, rate limiting, DNS revalidation, and all exceptions.
    def execute(url : String, uri : URI?, initial_dns_ips : Hash(String, Array(String)), redirect_count : Int32) : Result
      acquired = acquire_semaphore(url)
      return Vug.failure("Semaphore acquire failed", url, error_type: :fetch_error) unless acquired
      begin
        parsed_uri = uri || parse_uri(url)
        host = parsed_uri.hostname
        check_rate_and_dns(url, host, initial_dns_ips, redirect_count, parsed_uri)
      rescue ex : URI::Error
        @config.error("fetch_single(#{url})", "Invalid URL format: #{ex.message}")
        Vug.failure("Invalid URL", url, error_type: :invalid_url)
      rescue ex : Socket::Addrinfo::Error | OpenSSL::SSL::Error
        @config.error("fetch_single(#{url})", format_exception(ex, "Connection security error"))
        Vug.failure(ex.message || "Connection error", url, error_type: :fetch_error)
      rescue ex : IO::TimeoutError | IO::Error | Socket::Error
        @config.warning("fetch_single(#{url}): #{ex.message}")
        Vug.failure(ex.message || "Network error", url, error_type: :fetch_error)
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

    private def parse_uri(url : String) : URI
      URI.parse(url)
    rescue ex : URI::Error
      @config.error("fetch_single(#{url})", "Invalid URL format: #{ex.message}")
      raise ex
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

    private def perform_http_request(url : String, uri : URI, redirect_count : Int32) : Result
      client = @http_client_factory.create_client(uri)
      success = false

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
        success = true
      ensure
        @http_client_factory.release_client(uri, client, success: success)
      end
      result || Vug.failure("Unexpected HTTP error", url.to_s)
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

    private def process_response(url : String, response : HTTP::Client::Response) : Result
      content_type = response.content_type || "image/png"
      memory = IO::Memory.new
      IO.copy(response.body_io, memory, limit: @config.max_size)
      @image_processor.process_bytes(url, memory.to_slice, content_type)
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
  end
end
