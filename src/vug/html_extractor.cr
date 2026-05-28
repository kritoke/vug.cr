require "http/client"
require "uri"
require "html5"
require "sanitize"
require "digest"
require "./config"
require "./url_validator"
require "./types"
require "./manifest_extractor"
require "./diagnostics"
require "./data_url_handler"
require "./cache_manager"

module Vug
  class HtmlExtractor
    FAVICON_SELECTORS = [
      "link[rel~='icon']",
      "link[rel='shortcut icon']",
      "link[rel='apple-touch-icon']",
      "link[rel='apple-touch-icon-precomposed']",
      "link[type='image/x-icon']",
    ]

    def initialize(@config : Config = Config.default, manifest_extractor : ManifestExtractor? = nil, http_client_factory : HttpClientFactory? = nil, cache_manager : CacheManager? = nil, cache_coordinator : CacheCoordinator? = nil)
      @manifest_extractor = manifest_extractor || ManifestExtractor.new(@config)
      @http_client_factory = http_client_factory || HttpClientFactory.new(@config)
      @cache_coordinator = cache_coordinator || CacheCoordinator.new(@config, nil, cache_manager)
    end

    # Extract favicon information from a site's HTML.
    # Optionally accepts a custom timeout for slow servers.
    def extract_all(site_url : String, timeout : Time::Span? = nil) : Array(FaviconInfo)
      uri = validate_and_parse_url(site_url)
      return [] of FaviconInfo unless uri

      read_timeout = timeout || @config.html_fetch_timeout
      max_retries = @config.max_retries
      base_delay = @config.retry_base_delay
      max_delay = @config.retry_max_delay

      favicons = [] of FaviconInfo
      attempt = 0
      last_error : Exception? = nil

      loop do
        begin
          @config.debug("Fetching HTML from: #{site_url} (attempt #{attempt + 1})")
          client = @http_client_factory.create_client(uri, read_timeout)
          headers = build_html_headers

          client.get(uri.request_target, headers: headers) do |response|
            favicons = process_html_response(response, site_url)
          end
          return favicons
        rescue ex : IO::TimeoutError | Socket::Error | IO::Error | OpenSSL::SSL::Error
          last_error = ex
          if attempt < max_retries
            delay = calculate_backoff_delay(attempt, base_delay, max_delay)
            @config.debug("Transient error on #{site_url}: #{ex.message}. Retrying in #{delay.total_milliseconds.round}ms...")
            sleep(delay)
            attempt += 1
          else
            @config.debug("Max retries (#{max_retries}) reached for #{site_url}, giving up")
            log_error("extract_all(#{site_url})", ex)
            return [] of FaviconInfo
          end
        rescue ex : Exception
          # Non-transient error, don't retry
          log_error("extract_all(#{site_url})", ex)
          return [] of FaviconInfo
        end
      end

      favicons
    end

    # Calculate exponential backoff delay with jitter.
    private def calculate_backoff_delay(attempt : Int32, base_delay : Time::Span, max_delay : Time::Span) : Time::Span
      # Exponential backoff: base_delay * 2^attempt
      exponential = base_delay * (2 ** attempt)
      # Cap at max_delay
      capped = exponential > max_delay ? max_delay : exponential
      # Add jitter (0-25% of delay)
      jitter_ns = (rand * 0.25 * capped.total_nanoseconds).to_i64
      Time::Span.new(nanoseconds: capped.total_nanoseconds.to_i64 + jitter_ns)
    end

    private def validate_and_parse_url(site_url : String) : URI?
      clean_url = UrlProcessor.sanitize_feed_url(site_url)
      return debug_return("URL blocked by validator: #{clean_url}") unless UrlValidator.valid_url?(clean_url)

      parsed = URI.parse(clean_url)
      return debug_return("URL missing scheme: #{clean_url}") unless parsed.scheme
      parsed
    rescue ex : URI::Error
      @config.debug("Invalid URL for HTML extraction: #{clean_url} - #{ex.message}")
      nil
    end

    private def debug_return(msg : String)
      @config.debug(msg)
      nil
    end

    private def build_html_headers : HTTP::Headers
      HTTP::Headers{
        "User-Agent" => @config.user_agent,
        "Accept"     => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      }
    end

    private def process_html_response(response : HTTP::Client::Response, site_url : String) : Array(FaviconInfo)
      return [] of FaviconInfo unless response.status.success?

      favicons = [] of FaviconInfo
      html = fetch_html(response.body_io)
      return [] of FaviconInfo if html.empty?

      html_favicons = extract_favicons_from_html(html, site_url)
      favicons.concat(html_favicons)

      add_manifest_favicons(html, site_url, favicons)
      favicons
    end

    private def fetch_html(body_io : IO) : String
      memory = IO::Memory.new
      IO.copy(body_io, memory, limit: @config.max_size)
      html = memory.to_slice.to_s
      @config.debug("HTML fetched: #{html.size} bytes")
      html = sanitize_html(html)
      @config.debug("HTML sanitized: #{html.size} bytes")
      html
    rescue IO::TimeoutError
      @config.debug("HTML fetch timeout")
      ""
    end

    private def add_manifest_favicons(html : String, site_url : String, favicons : Array(FaviconInfo))
      return unless manifest_url = @manifest_extractor.extract_manifest_url(html, site_url)

      @config.debug("Found manifest: #{manifest_url}")
      if manifest_favicons = @manifest_extractor.extract_favicons_from_manifest(manifest_url)
        favicons.concat(manifest_favicons)
        @config.debug("Extracted #{manifest_favicons.size} favicons from manifest")
      end
    end

    private def log_error(context : String, ex : Exception, prefix : String? = nil)
      @config.error(context, Vug::Diagnostics.format_exception(ex, prefix))
      @config.debug("#{prefix || "Error"}: #{ex.message}")
    end

    # Backward compatibility method - returns first favicon only
    def extract(site_url : String) : String?
      favicons = extract_all(site_url)
      favicons.first?.try(&.url)
    end

    private def extract_favicons_from_html(html : String, base_url : String) : Array(FaviconInfo)
      favicons = [] of FaviconInfo
      doc = HTML5.parse(html)

      FAVICON_SELECTORS.each do |selector|
        nodes = doc.css(selector)
        next if nodes.empty?

        nodes.each do |node|
          href_attr = node["href"]?
          next if href_attr.nil?
          href = href_attr.val
          next if href.empty?
          process_favicon_link(href, node, base_url, favicons)
        end
      end

      favicons
    end

    private def process_favicon_link(href : String, node : HTML5::Node, base_url : String, favicons : Array(FaviconInfo))
      if DataUrlHandler.data_url?(href)
        process_data_url_favicon(href, favicons)
      else
        process_normal_favicon(node, href, base_url, favicons)
      end
    end

    private def process_data_url_favicon(href : String, favicons : Array(FaviconInfo))
      data_result = DataUrlHandler.extract_from_url(href, @config.max_size)
      return unless data_result

      data, media_type = data_result
      data_url_id = "data:#{Digest::SHA256.hexdigest(data.to_slice)}"
      favicon_info = FaviconInfo.new(url: data_url_id, sizes: nil, type: media_type, purpose: nil)
      @config.debug("Found data URL favicon: #{data_url_id}")
      favicons << favicon_info

      if saved_path = @config.save(data_url_id, data, media_type)
        @config.debug("Data URL favicon saved: #{saved_path}")
        @cache_coordinator.try(&.store(data_url_id, saved_path))
      end
    end

    private def process_normal_favicon(node : HTML5::Node, href : String, base_url : String, favicons : Array(FaviconInfo))
      normalized = UrlProcessor.resolve_and_normalize(href, base_url)
      return unless UrlProcessor.valid_scheme?(normalized)

      favicon_info = FaviconInfo.new(
        url: normalized,
        sizes: node["sizes"]?.try(&.val),
        type: node["type"]?.try(&.val),
        purpose: nil
      )
      favicons << favicon_info
    end

    private def sanitize_html(html : String) : String
      Sanitize::Policy::HTMLSanitizer.common.process(html)
    rescue ex : HTML5::HTMLException | URI::Error
      @config.debug("HTML sanitization failed: #{ex.message}")
      ""
    rescue ex : IO::Error | Socket::Error
      @config.debug("HTML processing failed: #{ex.message}")
      raise ex
    end
  end
end
