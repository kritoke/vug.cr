require "../src/vug.cr"
require "digest"

config = Vug::Config.new(
  on_load: ->(_u : String) : String? { nil },
  on_save: ->(_u : String, _data : Bytes, _ct : String) { "/tmp/#{Digest::SHA256.hexdigest(_u)}".as(String?) }
)

mem = Vug::MemoryCache.new
cm = Vug::CacheManager.new(config, mem)
coord = Vug::CacheCoordinator.new(config, mem, cm)

mem.set("a", "/m/a")
puts "coord.fetch_from_cache('a') => #{coord.fetch_from_cache("a")}"

coord.store_to_cache("b", "/m/b")
puts "mem.get('b') => #{mem.get("b")}"
puts "cm.get('b') => #{cm.get("b")}"

puts "CacheCoordinator smoke test done"
