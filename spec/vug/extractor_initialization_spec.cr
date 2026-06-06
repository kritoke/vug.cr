require "../spec_helper"
require "../../src/vug/html_extractor"
require "../../src/vug/manifest_extractor"
require "../../src/vug/http_client_factory"
require "../../src/vug/fetcher"
require "../../src/vug/cache_manager"
require "../../src/vug/url_processor"

describe Vug::HtmlExtractor do
  describe "#initialize" do
    it "creates instance with default config" do
      extractor = Vug::HtmlExtractor.new
      extractor.should_not be_nil
    end

    it "creates instance with custom config" do
      config = Vug::Config.new
      extractor = Vug::HtmlExtractor.new(config)
      extractor.should_not be_nil
    end

    it "creates instance with config and custom dependencies" do
      config = Vug::Config.new
      factory = Vug::HttpClientFactory.new(config)
      extractor = Vug::HtmlExtractor.new(config, Vug::HtmlExtractor::Dependencies.new(http_client_factory: factory))
      extractor.should_not be_nil
    end

    it "creates instance with config, dependencies, and cache coordinator" do
      config = Vug::Config.new
      factory = Vug::HttpClientFactory.new(config)
      coordinator = Vug::CacheCoordinator.new(config)
      extractor = Vug::HtmlExtractor.new(config, Vug::HtmlExtractor::Dependencies.new(
        http_client_factory: factory,
        cache_coordinator: coordinator
      ))
      extractor.should_not be_nil
    end
  end

  describe "#extract_all with timeout parameter" do
    it "accepts custom timeout parameter" do
      config = Vug::Config.new(max_retries: 0) # Disable retries for faster test
      extractor = Vug::HtmlExtractor.new(config)
      # Just verify the method accepts the parameter - the result will be empty due to invalid URL
      result = extractor.extract_all("https://invalid.invalid", 1.millisecond)
      result.should be_a(Array(Vug::FaviconInfo))
    end
  end
end

describe Vug::ManifestExtractor do
  describe "#initialize" do
    it "creates instance with config" do
      config = Vug::Config.new
      extractor = Vug::ManifestExtractor.new(config)
      extractor.should_not be_nil
    end

    it "creates instance with config and custom http_client_factory" do
      config = Vug::Config.new
      factory = Vug::HttpClientFactory.new(config)
      extractor = Vug::ManifestExtractor.new(config, factory)
      extractor.should_not be_nil
    end
  end
end

describe Vug::Fetcher do
  describe "#initialize" do
    it "creates instance with default config" do
      fetcher = Vug::Fetcher.new
      fetcher.should_not be_nil
    end

    it "creates instance with custom config" do
      config = Vug::Config.new
      fetcher = Vug::Fetcher.new(config)
      fetcher.should_not be_nil
    end

    it "creates instance with config and cache" do
      config = Vug::Config.new
      cache = Vug::MemoryCache.new
      fetcher = Vug::Fetcher.new(config, cache)
      fetcher.should_not be_nil
    end

    it "creates instance with config, cache, and custom dependencies" do
      config = Vug::Config.new
      cache = Vug::MemoryCache.new
      factory = Vug::HttpClientFactory.new(config)
      cache_manager = Vug::CacheManager.new(config, cache)
      redirect_handler = Vug::RedirectHandler::Default.new(config)
      fetcher = Vug::Fetcher.new(config, cache, factory, cache_manager, redirect_handler)
      fetcher.should_not be_nil
    end
  end
end

describe Vug::CacheManager do
  describe "#initialize" do
    it "creates instance with config" do
      config = Vug::Config.new
      cache_manager = Vug::CacheManager.new(config)
      cache_manager.should_not be_nil
    end

    it "creates instance with config and memory cache" do
      config = Vug::Config.new
      memory_cache = Vug::MemoryCache.new
      cache_manager = Vug::CacheManager.new(config, memory_cache)
      cache_manager.should_not be_nil
    end
  end
end
