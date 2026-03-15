require "./vug/config"
require "./vug/types"
require "./vug/fetcher"
require "./vug/html_extractor"
require "./vug/manifest_extractor"
require "./vug/favicon_collection"
require "./vug/cache"
require "./vug/image_validator"
require "./vug/advanced_image_validator"
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

  def self.fetch_for_site(site_url : String, config : Config = Config.new, cache : MemoryCache? = nil) : Result
    # Use best favicon strategy for backward compatibility
    if collection = fetch_all_favicons_for_site(site_url, config)
      if best_favicon = collection.best
        # Check if it's a data URL (already handled in extraction)
        if best_favicon.url.starts_with?("data:")
          # Data URL favicons are already saved during extraction
          if cached = config.load(best_favicon.url) || cache.try(&.get(best_favicon.url))
            return Vug.success(best_favicon.url, cached)
          end
        else
          # Regular URL - fetch it
          fetcher = Fetcher.new(config, cache)
          result = fetcher.fetch(best_favicon.url)
          if path = result.local_path
            cache.try(&.set(best_favicon.url, path))
            return result
          end
        end
      end
    end

    # Fallback chain if no favicons found in HTML/manifest
    fetcher = Fetcher.new(config, cache)
    clean_url = sanitize_url(site_url)

    host = extract_host(clean_url)
    return Vug.failure("Invalid URL", site_url) unless host

    # Try standard paths
    favicon_urls = DEFAULT_FAVICON_PATHS.map { |path_segment| "https://#{host}#{path_segment}" }
    favicon_urls.each do |url|
      if cached = config.load(url) || cache.try(&.get(url))
        config.debug("Found cached favicon: #{url}")
        return Vug.success(url, cached)
      end

      result = fetcher.fetch(url)
      if path = result.local_path
        cache.try(&.set(url, path))
        return result
      end
    end

    # Try DuckDuckGo
    duckduckgo_url = duckduckgo_favicon_url(host)
    config.debug("DuckDuckGo favicon URL: #{duckduckgo_url}")
    result = fetcher.fetch(duckduckgo_url)
    if path = result.local_path
      cache.try(&.set(duckduckgo_url, path))
      return result
    end

    # Final fallback to Google
    google_url = google_favicon_url(host)
    config.debug("Google favicon URL: #{google_url}")
    result = fetcher.fetch(google_url)
    if path = result.local_path
      cache.try(&.set(google_url, path))
      return result
    end

    # Ultimate fallback: generate placeholder SVG
    config.debug("No favicon found, generating placeholder for: #{host}")
    placeholder_data, content_type = PlaceholderGenerator.generate_for_domain(host)
    if saved_path = config.save("placeholder:#{host}", placeholder_data, content_type)
      cache.try(&.set("placeholder:#{host}", saved_path)) if cache
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
    if collection = fetch_all_favicons_for_site(site_url, config)
      if best_favicon = collection.best
        if best_favicon.url.starts_with?("data:")
          if cached = config.load(best_favicon.url) || cache.try(&.get(best_favicon.url))
            return Vug.success(best_favicon.url, cached)
          end
        else
          fetcher = Fetcher.new(config, cache)
          result = fetcher.fetch(best_favicon.url)
          if path = result.local_path
            cache.try(&.set(best_favicon.url, path))
            return result
          end
        end
      end
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
