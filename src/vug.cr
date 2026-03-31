require "uri"
require "./vug/config"
require "./vug/types"
require "./vug/url_validator"
require "./vug/http_client_factory"
require "./vug/url_processor"
require "./vug/cache_manager"
require "./vug/redirect_validator"
require "./vug/favicon_info"
require "./vug/fetcher"
require "./vug/html_extractor"
require "./vug/manifest_extractor"
require "./vug/favicon_collection"
require "./vug/cache"
require "./vug/image_validator"
require "./vug/data_url_handler"
require "./vug/placeholder_generator"

module Vug
  DEFAULT_FAVICON_PATHS = [
    "/favicon.ico",
    "/favicon.png",
    "/apple-touch-icon.png",
    "/apple-touch-icon-180x180.png",
  ]

  # Shared concurrency limiter for all Fetcher instances
  @@semaphore : Semaphore? = nil
  @@semaphore_mutex = Mutex.new

  class Semaphore
    def initialize(@limit : Int32)
      @channel = Channel(Nil).new(@limit)
      @limit.times { @channel.send(nil) }
    end

    def acquire : Nil
      @channel.receive
    end

    def release : Nil
      @channel.send(nil)
    end
  end

  def self.shared_semaphore(limit : Int32) : Semaphore
    @@semaphore_mutex.synchronize do
      @@semaphore ||= Semaphore.new(limit)
    end
  end

  def self.fetch(url : String, config : Config = Config.default, cache : MemoryCache? = nil) : Result
    http_client_factory = HttpClientFactory.new(config)
    fetcher = Fetcher.new(config, cache, http_client_factory)
    fetcher.fetch(url)
  end

  def self.site(site_url : String, config : Config = Config.default, cache : MemoryCache? = nil) : Result
    clean_url = UrlProcessor.sanitize_feed_url(site_url)
    http_client_factory = HttpClientFactory.new(config)
    cache_manager = CacheManager.new(config, cache)

    if result = try_extracted_favicon(clean_url, config, cache, http_client_factory, cache_manager)
      return result
    end

    if result = try_fallback_chain(clean_url, config, cache, http_client_factory, cache_manager)
      return result
    end

    generate_placeholder_fallback(clean_url, config, cache, cache_manager)
  end

  def self.favicons(site_url : String, config : Config = Config.default, http_client_factory : HttpClientFactory? = nil) : FaviconCollection?
    clean_url = UrlProcessor.sanitize_feed_url(site_url)
    factory = http_client_factory || HttpClientFactory.new(config)
    manifest_extractor = ManifestExtractor.new(config, factory)
    html_extractor = HtmlExtractor.new(config, manifest_extractor, factory)
    favicons = html_extractor.extract_all(clean_url)

    return if favicons.empty?

    collection = FaviconCollection.new
    collection.add_all(favicons)
    collection
  end

  def self.best(site_url : String, config : Config = Config.default, cache : MemoryCache? = nil) : Result
    clean_url = UrlProcessor.sanitize_feed_url(site_url)
    http_client_factory = HttpClientFactory.new(config)
    cache_manager = CacheManager.new(config, cache)

    if result = try_extracted_favicon(clean_url, config, cache, http_client_factory, cache_manager)
      return result
    end

    Vug.failure("No favicon found", site_url, error_type: :no_favicon_found)
  end

  def self.placeholder(site_url : String, config : Config = Config.default, cache : MemoryCache? = nil) : Result
    clean_url = UrlProcessor.sanitize_feed_url(site_url)
    host = extract_host(clean_url, config)
    return Vug.failure("Invalid URL", site_url, error_type: :invalid_url) unless host

    placeholder_data, content_type = PlaceholderGenerator.generate_for_domain(host)
    cache_manager = CacheManager.new(config, cache)
    if saved_path = config.save("placeholder:#{host}", placeholder_data, content_type)
      cache_manager.set("placeholder:#{host}", saved_path)
      return Vug.success("placeholder:#{host}", saved_path, content_type, placeholder_data)
    end

    Vug.failure("Placeholder generation failed", site_url, error_type: :placeholder_generation_failed)
  end

  def self.google_favicon_url(domain : String) : String
    Fetcher.google_favicon_url(domain)
  end

  def self.duckduckgo_favicon_url(domain : String) : String
    host = UrlProcessor.extract_host_from_url(domain) || domain
    encoded_host = URI.encode_path(host)
    "https://icons.duckduckgo.com/ip3/#{encoded_host}.ico"
  end

  private def self.try_extracted_favicon(site_url : String, config : Config, cache : MemoryCache?, http_client_factory : HttpClientFactory, cache_manager : CacheManager) : Result?
    collection = favicons(site_url, config, http_client_factory)
    return unless collection

    best = collection.best
    return unless best

    return fetch_data_url_favicon(best, config, cache_manager) if best.url.starts_with?("data:")

    fetcher = Fetcher.new(config, cache, http_client_factory)
    result = fetcher.fetch(best.url)
    return unless path = result.local_path

    cache.try(&.set(best.url, path))
    result
  end

  private def self.try_fallback_chain(site_url : String, config : Config, cache : MemoryCache?, http_client_factory : HttpClientFactory, cache_manager : CacheManager) : Result?
    host = extract_host(site_url, config)
    return unless host

    fetcher = Fetcher.new(config, cache, http_client_factory)

    if result = try_standard_paths(host, fetcher, cache_manager)
      return result
    end

    if result = try_duckduckgo(host, fetcher, cache_manager, config)
      return result
    end

    try_google(host, fetcher, cache_manager, config)
  end

  private def self.generate_placeholder_fallback(site_url : String, config : Config, cache : MemoryCache?, cache_manager : CacheManager) : Result
    host = extract_host(site_url, config)
    return Vug.failure("Invalid URL", site_url, error_type: :invalid_url) unless host

    config.debug("No favicon found, generating placeholder for: #{host}")
    placeholder_data, content_type = PlaceholderGenerator.generate_for_domain(host)

    if saved_path = config.save("placeholder:#{host}", placeholder_data, content_type)
      cache_manager.set("placeholder:#{host}", saved_path)
      return Vug.success("placeholder:#{host}", saved_path, content_type, placeholder_data)
    end

    Vug.failure("No favicon found and placeholder generation failed", site_url, error_type: :no_favicon_found)
  end

  private def self.fetch_data_url_favicon(favicon : FaviconInfo, config : Config, cache_manager : CacheManager) : Result?
    cached = cache_manager.get(favicon.url)
    return unless cached

    Vug.success(favicon.url, cached)
  rescue ex : URI::Error
    config.debug("Failed to fetch data URL favicon: #{ex.message}")
    nil
  end

  private def self.try_standard_paths(host : String, fetcher : Fetcher, cache_manager : CacheManager) : Result?
    DEFAULT_FAVICON_PATHS.each do |path_segment|
      url = "https://#{host}#{path_segment}"
      if result = fetch_with_cache(url, fetcher, cache_manager)
        return result
      end
    end
    nil
  end

  private def self.try_duckduckgo(host : String, fetcher : Fetcher, cache_manager : CacheManager, config : Config) : Result?
    url = duckduckgo_favicon_url(host)
    config.debug("DuckDuckGo favicon URL: #{url}")
    fetch_with_cache(url, fetcher, cache_manager)
  end

  private def self.try_google(host : String, fetcher : Fetcher, cache_manager : CacheManager, config : Config) : Result?
    url = google_favicon_url(host)
    config.debug("Google favicon URL: #{url}")
    fetch_with_cache(url, fetcher, cache_manager)
  end

  private def self.fetch_with_cache(url : String, fetcher : Fetcher, cache_manager : CacheManager) : Result?
    cached = cache_manager.get(url)
    return Vug.success(url, cached) if cached

    result = fetcher.fetch(url)
    return unless path = result.local_path

    cache_manager.set(url, path)
    result
  end

  private def self.extract_host(url : String, config : Config) : String?
    UrlProcessor.extract_host_from_url(url)
  rescue ex : URI::Error
    config.debug("Failed to extract host from URL: #{url} - #{ex.message}")
    nil
  end
end
