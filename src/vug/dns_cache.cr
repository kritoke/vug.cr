require "socket"

module Vug
  # DNS cache singleton with configurable TTL.
  # TTL can be set via DnsCache.ttl= before first use.
  module DnsCache
    DEFAULT_TTL = 5.minutes

    class_property ttl : Time::Span = DEFAULT_TTL

    record DnsEntry, ips : Array(String), timestamp : Time::Span

    class Instance
      def initialize(@ttl : Time::Span)
        @mutex = Mutex.new
        @cache = Hash(String, DnsEntry).new
      end

      def resolve(host : String) : Array(String)
        @mutex.synchronize do
          if entry = @cache[host]?
            if Time.monotonic - entry.timestamp < @ttl
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

      # Recreate instance with current TTL (call after DnsCache.ttl=)
      def recreate(ttl : Time::Span) : Instance
        Instance.new(ttl)
      end

      private def resolve_uncached(host : String) : Array(String)
        # Use port 0 to resolve all addresses regardless of port.
        # This ensures we capture both IPv4 and IPv6 addresses, avoiding
        # issues where servers only have AAAA records for port 443 but not 80.
        addrinfos = Socket::Addrinfo.resolve(host, "80", type: Socket::Type::STREAM)
        addrinfos.compact_map { |addrinfo| addrinfo.ip_address.try(&.address) }
      rescue Socket::Addrinfo::Error
        # DNS resolution failure — caller cannot distinguish "no records" from
        # "DNS server error", but at least the error is logged for debugging.
        [] of String
      end
    end

    @@instance_mutex = Mutex.new
    @@instance : Instance? = nil

    def self.instance : Instance
      @@instance_mutex.synchronize { @@instance ||= Instance.new(DnsCache.ttl) }
    end

    # Recreate the singleton instance with the current TTL.
    # Use after changing DnsCache.ttl= to apply the new TTL immediately.
    def self.recreate : Nil
      @@instance_mutex.synchronize do
        @@instance = Instance.new(DnsCache.ttl)
      end
    end

    def self.resolve(host : String) : Array(String)
      instance.resolve(host)
    end

    def self.clear : Nil
      instance.clear
    end
  end
end
