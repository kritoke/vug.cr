require "uri"
require "./vug/config"
require "./vug/types"
require "./vug/url_validator"
require "./vug/http_client_factory"
require "./vug/url_processor"
require "./vug/cache_manager"
require "./vug/redirect_validator"
require "./vug/favicon_info"
require "./vug/semaphore"
require "./vug/fetcher"
require "./vug/html_extractor"
require "./vug/manifest_extractor"
require "./vug/favicon_collection"
require "./vug/cache"
require "./vug/image_validator"
require "./vug/data_url_handler"
require "./vug/placeholder_generator"
require "./vug/favicon_resolver"

module Vug
  DEFAULT_FAVICON_PATHS = [
    "/favicon.ico",
    "/favicon.png",
    "/apple-touch-icon.png",
    "/apple-touch-icon-180x180.png",
  ]

  class SharedState
    def self.instance : self
      @@instance ||= new
    end

    def self.instance=(value : self)
      @@instance = value
    end

    def initialize
      @semaphore_mutex = Mutex.new
    end

    def semaphore(limit : Int32) : Semaphore
      @semaphore_mutex.synchronize do
        @semaphore ||= Semaphore.new(limit)
      end
    end

    private getter semaphore_mutex : Mutex
    private property semaphore : Semaphore? = nil
  end

  def self.shared_semaphore(limit : Int32) : Semaphore
    SharedState.instance.semaphore(limit)
  end

  def self.fetch(url : String, config : Config = Config.default, cache : MemoryCache? = nil) : Result
    fetcher = Fetcher.new(config, cache)
    fetcher.fetch(url)
  end

  def self.site(site_url : String, config : Config = Config.default, cache : MemoryCache? = nil) : Result
    resolver = FaviconResolver.new(config, cache)
    resolver.site(site_url)
  end

  def self.favicons(site_url : String, config : Config = Config.default, http_client_factory : HttpClientFactory? = nil) : FaviconCollection?
    factory = http_client_factory || HttpClientFactory.new(config)
    html_extractor = HtmlExtractor.new(config, nil, factory)
    favicons = html_extractor.extract_all(UrlProcessor.sanitize_feed_url(site_url))

    return if favicons.empty?

    collection = FaviconCollection.new
    collection.add_all(favicons)
    collection
  end

  def self.best(site_url : String, config : Config = Config.default, cache : MemoryCache? = nil) : Result
    resolver = FaviconResolver.new(config, cache)
    resolver.best(site_url)
  end

  def self.placeholder(site_url : String, config : Config = Config.default, cache : MemoryCache? = nil) : Result
    clean_url = UrlProcessor.sanitize_feed_url(site_url)
    host = UrlProcessor.extract_host_from_url(clean_url)
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
    FaviconResolver.google_favicon_url(domain)
  end

  def self.duckduckgo_favicon_url(domain : String) : String
    FaviconResolver.duckduckgo_favicon_url(domain)
  end
end
