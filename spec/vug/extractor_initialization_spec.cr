require "../spec_helper"
require "../../src/vug/html_extractor"
require "../../src/vug/manifest_extractor"
require "../../src/vug/http_client_factory"
require "../../src/vug/fetcher"
require "../../src/vug/cache_manager"

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
      extractor = Vug::HtmlExtractor.new(config, nil, factory)
      extractor.should_not be_nil
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
      redirect_validator = Vug::RedirectValidator.new(config)
      fetcher = Vug::Fetcher.new(config, cache, factory, cache_manager, redirect_validator)
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
