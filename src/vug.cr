require "./vug/config"
require "./vug/types"
require "./vug/url_validator"
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

  def self.fetch(url : String, config : Config = Config.new, cache : MemoryCache? = nil) : Result
    fetcher = Fetcher.new(config, cache)
    fetcher.fetch(url)
  end

  def self.site(site_url : String, config : Config = Config.new, cache : MemoryCache? = nil) : Result
    if result = try_extracted_favicon(site_url, config, cache)
      return result
    end

    if result = try_fallback_chain(site_url, config, cache)
      return result
    end

    generate_placeholder_fallback(site_url, config, cache)
  end

  def self.favicons(site_url : String, config : Config = Config.new) : FaviconCollection?
    extractor = HtmlExtractor.new(config)
    favicons = extractor.extract_all(sanitize_url(site_url))

    return if favicons.empty?

    collection = FaviconCollection.new
    collection.add_all(favicons)
    collection
  end

  def self.best(site_url : String, config : Config = Config.new, cache : MemoryCache? = nil) : Result
    if result = try_extracted_favicon(site_url, config, cache)
      return result
    end

    Vug.failure("No favicon found", site_url)
  end

  def self.placeholder(site_url : String, config : Config = Config.new, cache : MemoryCache? = nil) : Result
    clean_url = sanitize_url(site_url)
    host = extract_host(clean_url)
    return Vug.failure("Invalid URL", site_url) unless host

    placeholder_data, content_type = PlaceholderGenerator.generate_for_domain(host)
    if saved_path = config.save("placeholder:#{host}", placeholder_data, content_type)
      cache.try(&.set("placeholder:#{host}", saved_path)) if cache
      return Vug.success("placeholder:#{host}", saved_path, content_type, placeholder_data)
    end

    Vug.failure("Placeholder generation failed", site_url)
  end

  def self.fetch_for_site(site_url : String, config : Config = Config.new, cache : MemoryCache? = nil) : Result
    if result = try_extracted_favicon(site_url, config, cache)
      return result
    end

    if result = try_fallback_chain(site_url, config, cache)
      return result
    end

    generate_placeholder_fallback(site_url, config, cache)
  end

  private def self.try_extracted_favicon(site_url : String, config : Config, cache : MemoryCache?) : Result?
    collection = fetch_all_favicons_for_site(site_url, config)
    return unless collection

    best = collection.best
    return unless best

    return fetch_data_url_favicon(best, config, cache) if best.url.starts_with?("data:")

    fetcher = Fetcher.new(config, cache)
    result = fetcher.fetch(best.url)
    return unless path = result.local_path

    cache.try(&.set(best.url, path))
    result
  end

  private def self.fetch_data_url_favicon(favicon : FaviconInfo, config : Config, cache : MemoryCache?) : Result?
    cached = config.load(favicon.url) || cache.try(&.get(favicon.url))
    return unless cached

    Vug.success(favicon.url, cached)
  end

  private def self.try_fallback_chain(site_url : String, config : Config, cache : MemoryCache?) : Result?
    host = extract_host(sanitize_url(site_url))
    return unless host

    fetcher = Fetcher.new(config, cache)

    if result = try_standard_paths(host, fetcher, config, cache)
      return result
    end

    if result = try_duckduckgo(host, fetcher, config, cache)
      return result
    end

    try_google(host, fetcher, config, cache)
  end

  private def self.try_standard_paths(host : String, fetcher : Fetcher, config : Config, cache : MemoryCache?) : Result?
    DEFAULT_FAVICON_PATHS.each do |path_segment|
      url = "https://#{host}#{path_segment}"
      cached = config.load(url) || cache.try(&.get(url))
      return Vug.success(url, cached) if cached

      result = fetcher.fetch(url)
      if path = result.local_path
        cache.try(&.set(url, path))
        return result
      end
    end
    nil
  end

  private def self.try_duckduckgo(host : String, fetcher : Fetcher, config : Config, cache : MemoryCache?) : Result?
    url = duckduckgo_favicon_url(host)
    config.debug("DuckDuckGo favicon URL: #{url}")
    result = fetcher.fetch(url)
    return unless path = result.local_path

    cache.try(&.set(url, path))
    result
  end

  private def self.try_google(host : String, fetcher : Fetcher, config : Config, cache : MemoryCache?) : Result?
    url = google_favicon_url(host)
    config.debug("Google favicon URL: #{url}")
    result = fetcher.fetch(url)
    return unless path = result.local_path

    cache.try(&.set(url, path))
    result
  end

  private def self.generate_placeholder_fallback(site_url : String, config : Config, cache : MemoryCache?) : Result
    host = extract_host(sanitize_url(site_url))
    return Vug.failure("Invalid URL", site_url) unless host

    config.debug("No favicon found, generating placeholder for: #{host}")
    placeholder_data, content_type = PlaceholderGenerator.generate_for_domain(host)

    if saved_path = config.save("placeholder:#{host}", placeholder_data, content_type)
      cache.try(&.set("placeholder:#{host}", saved_path))
      return Vug.success("placeholder:#{host}", saved_path, content_type, placeholder_data)
    end

    Vug.failure("No favicon found and placeholder generation failed", site_url)
  end

  def self.fetch_all_favicons_for_site(site_url : String, config : Config = Config.new) : FaviconCollection?
    extractor = HtmlExtractor.new(config)
    favicons = extractor.extract_all(sanitize_url(site_url))

    return if favicons.empty?

    collection = FaviconCollection.new
    collection.add_all(favicons)
    collection
  end

  def self.fetch_best_favicon_for_site(site_url : String, config : Config = Config.new, cache : MemoryCache? = nil) : Result
    if result = try_extracted_favicon(site_url, config, cache)
      return result
    end

    Vug.failure("No favicon found", site_url)
  end

  def self.generate_placeholder_for_site(site_url : String, config : Config = Config.new, cache : MemoryCache? = nil) : Result
    clean_url = sanitize_url(site_url)
    host = extract_host(clean_url)
    return Vug.failure("Invalid URL", site_url) unless host

    placeholder_data, content_type = PlaceholderGenerator.generate_for_domain(host)
    if saved_path = config.save("placeholder:#{host}", placeholder_data, content_type)
      cache.try(&.set("placeholder:#{host}", saved_path)) if cache
      return Vug.success("placeholder:#{host}", saved_path, content_type, placeholder_data)
    end

    Vug.failure("Placeholder generation failed", site_url)
  end

  def self.google_favicon_url(domain : String) : String
    Fetcher.google_favicon_url(domain)
  end

  def self.duckduckgo_favicon_url(domain : String) : String
    host = domain.gsub(/\/feed\/?$/, "")
    if host.starts_with?("http")
      parsed = URI.parse(host)
      host = parsed.host || host
    end
    "https://icons.duckduckgo.com/ip3/#{host}.ico"
  end

  private def self.sanitize_url(url : String) : String
    url.gsub(/\/feed\/?$/, "")
  end

  private def self.extract_host(url : String) : String?
    parsed = URI.parse(sanitize_url(url))
    parsed.host
  rescue
    nil
  end
end
