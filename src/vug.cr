require "./vug/config"
require "./vug/types"
require "./vug/fetcher"
require "./vug/html_extractor"
require "./vug/cache"
require "./vug/image_validator"

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
    fetcher = Fetcher.new(config, cache)
    extractor = HtmlExtractor.new(config)

    clean_url = site_url.gsub(/\/feed\/?$/, "")

    host = extract_host(clean_url)
    return Vug.failure("Invalid URL", site_url) unless host

    favicon_urls = DEFAULT_FAVICON_PATHS.map { |path| "https://#{host}#{path}" }

    favicon_urls.each do |url|
      if cached = config.load(url) || cache.try(&.get(url))
        config.debug("Found cached favicon: #{url}")
        return Vug.success(url, cached)
      end
    end

    if html_favicon = extractor.extract(clean_url)
      config.debug("Found HTML favicon: #{html_favicon}")
      result = fetcher.fetch(html_favicon)
      if path = result.local_path
        cache.try(&.set(html_favicon, path))
        return result
      end
    end

    result = fetcher.fetch(favicon_urls.first)
    return result if result.local_path

    if html_favicon
      config.debug("No HTML favicon found for: #{clean_url}")
    end

    google_url = Fetcher.google_favicon_url(host)
    config.debug("Google favicon URL: #{google_url}")
    result = fetcher.fetch(google_url)
    if path = result.local_path
      cache.try(&.set(google_url, path))
      return result
    end

    Vug.failure("No favicon found", site_url)
  end

  def self.google_favicon_url(domain : String) : String
    Fetcher.google_favicon_url(domain)
  end

  private def self.extract_host(url : String) : String?
    parsed = URI.parse(url.gsub(/\/feed\/?$/, ""))
    parsed.host
  rescue
    nil
  end
end
