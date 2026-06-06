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
require "./retry_helpers"

module Vug
  class HtmlExtractor
    FAVICON_SELECTORS = [
      "link[rel~='icon']",
      "link[rel='shortcut icon']",
      "link[rel='apple-touch-icon']",
      "link[rel='apple-touch-icon-precomposed']",
      "link[type='image/x-icon']",
    ]

    # Injectable dependencies for HtmlExtractor.
    # All fields default to nil; the constructor wires defaults when nil.
    record Dependencies,
      manifest_extractor : ManifestExtractor? = nil,
      http_client_factory : HttpClientFactory? = nil,
      cache_coordinator : CacheCoordinator? = nil

    def initialize(@config : Config = Config.default, deps : Dependencies = Dependencies.new)
      @manifest_extractor = deps.manifest_extractor || ManifestExtractor.new(@config)
      @http_client_factory = deps.http_client_factory || HttpClientFactory.new(@config)
      @cache_coordinator = deps.cache_coordinator || CacheCoordinator.new(@config)
    end

    # Extract favicon information from a site's HTML.
    # Optionally accepts a custom timeout for slow servers.
    def extract_all(site_url : String, timeout : Time::Span? = nil) : Array(FaviconInfo)
      uri = parse_validated_url(site_url)
      return [] of FaviconInfo unless uri

      html = fetch_html_with_retry(site_url, uri, timeout || @config.html_fetch_timeout)
      return [] of FaviconInfo if html.empty?

      extract_favicons_from_html(html, site_url)
    end

    # Fetch HTML content with retry logic for transient failures.
    # Returns the sanitized HTML string, or "" on any error.
    private def fetch_html_with_retry(site_url : String, uri : URI, timeout : Time::Span) : String
      RetryHelpers.with_retry(
        max_retries: @config.max_retries,
        base_delay: @config.retry_base_delay,
        max_delay: @config.retry_max_delay,
        on_retry: ->(_attempt : Int32, ex : Exception, delay : Time::Span) {
          @config.debug("Transient error on #{site_url}: #{ex.message}. Retrying in #{delay.total_milliseconds.round}ms...")
          nil
        }
      ) do
        perform_html_request(site_url, uri, timeout)
      end
    rescue ex : Exception
      @config.debug("HTML fetch failed for #{site_url}: #{ex.message}")
      ""
    end

    # Perform a single HTTP request and return the response body as HTML.
    # Returns "" on non-success status or IO errors.
    private def perform_html_request(site_url : String, uri : URI, timeout : Time::Span) : String
      client : HTTP::Client? = nil
      begin
        @config.debug("Fetching HTML from: #{site_url}")
        client = @http_client_factory.create_client(uri, timeout)
        body = ""
        client.get(uri.request_target, headers: build_html_headers) do |response|
          return "" unless response.status.success?
          body = fetch_html(response.body_io)
        end
        body
      ensure
        client.try(&.close)
      end
    end

    private def parse_validated_url(site_url : String) : URI?
      UrlProcessor.parse_and_validate(site_url) || debug_return("URL validation failed: #{site_url}")
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

    # Extract favicons from raw HTML content: parse DOM, find icon links,
    # and merge any manifest-discovered favicons.
    private def extract_favicons_from_html(html : String, site_url : String) : Array(FaviconInfo)
      favicons = extract_html_favicons(html, site_url)
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
    rescue ex : IO::TimeoutError | IO::Error | Socket::Error
      @config.debug("HTML fetch/IO error: #{ex.class} - #{ex.message}")
      ""
    end

    private def add_manifest_favicons(html : String, site_url : String, favicons : Array(FaviconInfo))
      return unless manifest_url = @manifest_extractor.extract_manifest_url(html, site_url)

      @config.debug("Found manifest: #{manifest_url}")
      if manifest_favicons = @manifest_extractor.extract_manifest_favicons(manifest_url)
        favicons.concat(manifest_favicons)
        @config.debug("Extracted #{manifest_favicons.size} favicons from manifest")
      end
    end

    # Backward compatibility method - returns first favicon only
    def extract(site_url : String) : String?
      favicons = extract_all(site_url)
      favicons.first?.try(&.url)
    end

    private def extract_html_favicons(html : String, base_url : String) : Array(FaviconInfo)
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
        process_data_favicon(href, favicons)
      else
        process_normal_favicon(node, href, base_url, favicons)
      end
    end

    private def process_data_favicon(href : String, favicons : Array(FaviconInfo))
      data_result = DataUrlHandler.extract_from_url(href, @config.max_size)
      return unless data_result

      data, media_type = data_result
      data_url_id = HtmlExtractor.data_url_identifier(data)
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

    # Generate a stable synthetic URL identifier for a data-URL resource.
    # Uses SHA256 of the content bytes, prefixed with "data:" to distinguish
    # from real URLs. Suitable as a cache key.
    def self.data_url_identifier(data : Bytes) : String
      "data:#{Digest::SHA256.hexdigest(data.to_slice)}"
    end

    private def sanitize_html(html : String) : String
      Sanitize::Policy::HTMLSanitizer.common.process(html)
    rescue ex : HTML5::HTMLException | URI::Error | IO::Error | Socket::Error
      @config.debug("HTML sanitization failed: #{ex.message}")
      ""
    end
  end
end
