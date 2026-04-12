require "../spec_helper"
require "../../src/vug/cache_coordinator"
require "../../src/vug/cache_manager"

class TestCMStore1 < Vug::CacheManager
  def initialize(mem)
    super(Vug::Config.new(on_load: ->(_url : String) : String? { nil }), mem)
    @called = false
  end

  def set(_url, path)
    @called = true
    super
  end

  def called?
    @called
  end
end

class TestCMStore2 < Vug::CacheManager
  def initialize(mem)
    super(Vug::Config.new(on_load: ->(_url : String) : String? { nil }), mem)
    @called = false
  end

  def set(_url, path)
    @called = true
    super
  end

  def called?
    @called
  end
end

describe Vug::CacheCoordinator do
  it "store_to_cache stores to memory cache and calls cache_manager.set" do
    mem = Vug::MemoryCache.new
    test_cm = TestCMStore1.new(mem)

    coord = Vug::CacheCoordinator.new(Vug::Config.default, mem, test_cm)
    coord.store_to_cache("https://example.com/favicon.ico", "/favicons/example.png")

    test_cm.called?.should be_true
    mem.get("https://example.com/favicon.ico").should eq("/favicons/example.png")
  end

  it "store_to_cache does not store relative paths in memory cache" do
    mem = Vug::MemoryCache.new
    test_cm = TestCMStore2.new(mem)

    coord = Vug::CacheCoordinator.new(Vug::Config.default, mem, test_cm)
    coord.store_to_cache("https://example.com/favicon.ico", "relative/path.png")

    # Memory cache should not contain the relative path
    mem.get("https://example.com/favicon.ico").should be_nil
    test_cm.called?.should be_true
  end
end
