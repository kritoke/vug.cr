require "socket"

module Vug
  module DnsCache
    DNS_CACHE_TTL = 30.seconds

    @@cache = Hash(String, {Array(String), Time::Span}).new
    @@mutex = Mutex.new

    def self.resolve(host : String) : Array(String)
      @@mutex.synchronize do
        if entry = @@cache[host]?
          ips, timestamp = entry
          if Time.monotonic - timestamp < DNS_CACHE_TTL
            return ips
          end
        end
      end

      ips = resolve_uncached(host)

      @@mutex.synchronize do
        @@cache[host] = {ips, Time.monotonic}
      end

      ips
    end

    def self.clear : Nil
      @@mutex.synchronize { @@cache.clear }
    end

    private def self.resolve_uncached(host : String) : Array(String)
      addrinfos = Socket::Addrinfo.resolve(host, "80", type: Socket::Type::STREAM)
      addrinfos.compact_map { |addrinfo| addrinfo.ip_address.try(&.to_s) }
    rescue Socket::Addrinfo::Error
      [] of String
    end
  end
end
