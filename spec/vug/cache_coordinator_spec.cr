require "../spec_helper"
require "../../src/vug/cache_coordinator"
require "../../src/vug/config"

class TestCM
  def get(url) : String?; "/cm/#{url}"; end
  def set(url, path); end
end

class TestMem
  def initialize
    @h = {} of String => String
  end

  def get(url) : String?; @h[url]; end
  def set(url, path); @h[url] = path; end
end

class TestMemWithValue < TestMem
  def initialize
    super
    @h["u"] = "/m/u"
  end
end

class TestCMNil
  def get(url) : String?; nil; end
  def set(url, path); end
end

class TestCMWrapperClass
  @cm : TestCM

  def initialize(cm : TestCM)
    @cm = cm
  end

  def get(url) : String?
    @cm.get(url)
  end

  def set(url, path)
    @cm.set(url, path)
  end
end

describe Vug::CacheCoordinator do
  it "prefers cache_manager over memory cache" do
    # Use real CacheManager wrapper around our TestCM via a config shim
    config = Vug::Config.new(on_load: ->(url : String) : String? { "/cm/#{url}" })
    cache_manager = Vug::CacheManager.new(config, nil)
    coord = Vug::CacheCoordinator.new(Vug::Config.default, nil, cache_manager)
    coord.fetch_from_cache("u").should eq("/cm/u")
  end

  it "falls back to memory cache" do
    # Use real CacheManager with nil on_load to force fallback
    config = Vug::Config.new(on_load: ->(url : String) : String? { nil })
    cache_manager = Vug::CacheManager.new(config, nil)
    mem_cache = Vug::MemoryCache.new
    mem_cache.set("u", "/m/u")
    coord = Vug::CacheCoordinator.new(Vug::Config.default, mem_cache, cache_manager)
    coord.fetch_from_cache("u").should eq("/m/u")
  end
end
