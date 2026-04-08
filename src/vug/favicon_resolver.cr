module Vug
  class FaviconResolver
    def initialize(@config : Config = Config.default, cache : MemoryCache? = nil)
      @http_client_factory = HttpClientFactory.new(@config)
      @cache_manager = CacheManager.new(@config, cache)
      @fetcher = Fetcher.new(@config, cache, @http_client_factory)
      @html_fetcher = HtmlExtractor.new(@config, nil, @http_client_factory, @cache_manager)
    end

    def site(url : String) : Result
      clean_url = UrlProcessor.sanitize_feed_url(url)

      if result = try_extracted_favicon(clean_url)
        return result
      end

      if result = try_fallback_chain(clean_url)
        return result
      end

      generate_placeholder_fallback(clean_url)
    end

    def best(url : String) : Result
      clean_url = UrlProcessor.sanitize_feed_url(url)

      if result = try_extracted_favicon(clean_url)
        return result
      end

      Vug.failure("No favicon found", url, error_type: :no_favicon_found)
    end

    def extract_favicon_collection(url : String) : FaviconCollection?
      clean_url = UrlProcessor.sanitize_feed_url(url)
      favicons = @html_fetcher.extract_all(clean_url)
      return if favicons.empty?

      collection = FaviconCollection.new
      collection.add_all(favicons)
      collection
    end

    private def try_extracted_favicon(site_url : String) : Result?
      collection = extract_favicon_collection(site_url)
      return unless collection

      best = collection.best
      return unless best

      return fetch_data_url_favicon(best) if best.url.starts_with?("data:")

      result = @fetcher.fetch(best.url)
      return unless path = result.local_path

      @cache_manager.set(best.url, path)
      result
    end

    private def try_fallback_chain(site_url : String) : Result?
      host = extract_host(site_url)
      return unless host

      if result = try_standard_paths(host)
        return result
      end

      if result = try_duckduckgo(host)
        return result
      end

      try_google(host)
    end

    private def try_standard_paths(host : String) : Result?
      DEFAULT_FAVICON_PATHS.each do |path_segment|
        url = "https://#{host}#{path_segment}"
        if result = fetch_with_cache(url)
          return result
        end
      end
      nil
    end

    private def try_duckduckgo(host : String) : Result?
      url = self.class.duckduckgo_favicon_url(host)
      @config.debug("DuckDuckGo favicon URL: #{url}")
      fetch_with_cache(url)
    end

    private def try_google(host : String) : Result?
      url = self.class.google_favicon_url(host)
      @config.debug("Google favicon URL: #{url}")
      fetch_with_cache(url)
    end

    private def fetch_with_cache(url : String) : Result?
      cached = @cache_manager.get(url)
      return Vug.success(url, cached) if cached

      result = @fetcher.fetch(url)
      return unless path = result.local_path

      @cache_manager.set(url, path)
      result
    end

    private def fetch_data_url_favicon(favicon : FaviconInfo) : Result?
      if cached = @cache_manager.get(favicon.url)
        return Vug.success(favicon.url, cached)
      end

      if path = @config.load(favicon.url)
        @cache_manager.set(favicon.url, path)
        return Vug.success(favicon.url, path)
      end

      nil
    end

    private def generate_placeholder_fallback(site_url : String) : Result
      host = extract_host(site_url)
      return Vug.failure("Invalid URL", site_url, error_type: :invalid_url) unless host

      @config.debug("No favicon found, generating placeholder for: #{host}")
      placeholder_data, content_type = PlaceholderGenerator.generate_for_domain(host)

      if saved_path = @config.save("placeholder:#{host}", placeholder_data, content_type)
        @cache_manager.set("placeholder:#{host}", saved_path)
        return Vug.success("placeholder:#{host}", saved_path, content_type, placeholder_data)
      end

      Vug.failure("No favicon found and placeholder generation failed", site_url, error_type: :no_favicon_found)
    end

    private def extract_host(url : String) : String?
      UrlProcessor.extract_host_from_url(url)
    rescue ex : URI::Error
      @config.debug("Failed to extract host from URL: #{url} - #{ex.message}")
      nil
    end

    def self.google_favicon_url(domain : String) : String
      host = UrlProcessor.extract_host_from_url(domain) || domain
      encoded_host = URI.encode_www_form(host)
      "https://www.google.com/s2/favicons?domain=#{encoded_host}&sz=256"
    end

    def self.duckduckgo_favicon_url(domain : String) : String
      host = UrlProcessor.extract_host_from_url(domain) || domain
      encoded_host = URI.encode_path(host)
      "https://icons.duckduckgo.com/ip3/#{encoded_host}.ico"
    end
  end
end
