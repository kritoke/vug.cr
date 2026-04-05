require "socket"

module Vug
  module DnsCache
    DNS_CACHE_TTL = 30.seconds

    record DnsEntry, ips : Array(String), timestamp : Time::Span

    class Instance
      def initialize
        @mutex = Mutex.new
        @cache = Hash(String, DnsEntry).new
      end

      def resolve(host : String) : Array(String)
        @mutex.synchronize do
          if entry = @cache[host]?
            if Time.monotonic - entry.timestamp < DNS_CACHE_TTL
              return entry.ips
            end
          end

          ips = resolve_uncached(host)
          @cache[host] = DnsEntry.new(ips, Time.monotonic)
          ips
        end
      end

      def clear : Nil
        @mutex.synchronize { @cache.clear }
      end

      private def resolve_uncached(host : String) : Array(String)
        addrinfos = Socket::Addrinfo.resolve(host, "80", type: Socket::Type::STREAM)
        addrinfos.compact_map { |addrinfo| addrinfo.ip_address.try(&.address) }
      rescue Socket::Addrinfo::Error
        [] of String
      end
    end

    def self.instance : Instance
      @@instance ||= Instance.new
    end

    def self.resolve(host : String) : Array(String)
      instance.resolve(host)
    end

    def self.clear : Nil
      instance.clear
    end
  end
end
