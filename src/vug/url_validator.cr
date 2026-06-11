require "uri"
require "socket"
require "./dns_cache"
require "./config"

module Vug
  module UrlValidator
    def self.private_ip?(ip : String) : Bool
      return true if ip == "0.0.0.0"

      # Handle IPv4-mapped IPv6 addresses like ::ffff:192.168.0.1
      if ip.starts_with?("::ffff:")
        ipv4_part = ip.split("::ffff:")[1]?
        return private_ip?(ipv4_part) if ipv4_part
      end

      # Fast-path for IPv4 dotted literals
      return private_ipv4?(ip) if ip =~ /^\d{1,3}(?:\.\d{1,3}){3}$/

      # Handle IPv6 addresses
      return private_ipv6?(ip) if ip.includes?(":")

      # Fallback to Socket parsing for other forms
      addr = Socket::IPAddress.new(ip, 0) rescue nil
      return false unless addr
      addr.loopback? || addr.private? || addr.link_local?
    rescue
      false
    end

    # Check if an IPv4 address is in a private/reserved range
    private def self.private_ipv4?(ip : String) : Bool
      octets = ip.split(".").map(&.to_u32)
      return false unless octets.all? { |octet| octet <= 255_u32 }
      ip_int_u = ((octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]).to_u32

      masks = [
        {mask: 0xff000000_u32, value: 0x0a000000_u32}, # 10.0.0.0/8
        {mask: 0xfff00000_u32, value: 0xac100000_u32}, # 172.16.0.0/12
        {mask: 0xffff0000_u32, value: 0xc0a80000_u32}, # 192.168.0.0/16
        {mask: 0xff000000_u32, value: 0x7f000000_u32}, # 127.0.0.0/8 loopback
        {mask: 0xffc00000_u32, value: 0x64400000_u32}, # 100.64.0.0/10 CGN
        {mask: 0xfffe0000_u32, value: 0xc6120000_u32}, # 198.18.0.0/15 benchmark
        {mask: 0xffff0000_u32, value: 0xa9fe0000_u32}, # 169.254.0.0/16 link-local
        {mask: 0xf0000000_u32, value: 0xe0000000_u32}, # 224.0.0.0/4 multicast
        {mask: 0xf0000000_u32, value: 0xf0000000_u32}, # 240.0.0.0/4 reserved
      ]

      masks.any? { |mask| (ip_int_u & mask[:mask]) == mask[:value] }
    end

    # Check if an IPv6 address is in a private/reserved range
    private def self.private_ipv6?(ip : String) : Bool
      # Strip brackets for IPv6 URL format (e.g., [::1] -> ::1)
      normalized = ip.downcase.strip
      if normalized.starts_with?("[") && normalized.ends_with?("]")
        normalized = normalized[1...-1]
      end

      # Loopback: ::1
      return true if normalized == "::1"

      # Unique Local Addresses (ULA): fc00::/7 covers fc00–fcff and fd00–fdff
      return true if normalized.starts_with?("fc") || normalized.starts_with?("fd")

      # Link-local: fe80::/10
      return true if normalized.starts_with?("fe80")

      # Multicast: ff00::/8
      return true if normalized.starts_with?("ff")

      # Unspecified: ::
      normalized == "::"
    end

    def self.valid_url?(url : String) : Bool
      uri = URI.parse(url)
      return false unless valid_scheme?(uri.scheme)

      host = uri.hostname
      host = normalize_host(host)

      return false if dangerous_host?(host)
      true
    rescue URI::Error
      false
    end

    def self.revalidate_url?(url : String) : Bool
      uri = URI.parse(url)
      host = normalize_host(uri.hostname)
      return false if host.nil? || host.empty?

      return true if localhost_like?(host)

      # If host is a literal IP, check directly
      if host && literal_ip_string?(host)
        return false if private_ip?(host)
      end

      ips = DnsCache.resolve(host) if host
      return false if ips.nil? || ips.empty?

      !ips.any? { |ip| private_ip?(ip) }
    rescue URI::Error
      false
    end

    def self.resolves_to_private_ip?(host : String) : Bool
      host = normalize_host(host)

      # If host contains a dot or colon, it's either an IP literal or a fully
      # qualified domain (FQDN). For FQDNs (contains dot but not a literal IP)
      # we avoid DNS resolution in order to not fail in offline/test envs and
      # treat them as non-private. If it's a literal IP, evaluate directly.
      if host && (host.includes?(".") || host.includes?(":"))
        return private_ip?(host) if literal_ip_string?(host)
        return false
      end

      # For short hostnames (no dots/colons), perform DNS resolution. Empty
      # results are treated as private (defense-in-depth).
      return true if host.nil?
      ips = DnsCache.resolve(host)
      return true if ips.empty?

      ips.any? { |ip| private_ip?(ip) }
    end

    def self.valid_scheme?(scheme : String?) : Bool
      return false if scheme.nil?
      ["http", "https"].includes?(scheme.downcase)
    end

    # Parse a URL string, returning `nil` on `URI::Error` instead of raising.
    # Callers handle the nil case at the appropriate log level for their
    # context (Fetcher logs at debug, SingleRequest logs at error).
    def self.parse_or_nil(url : String) : URI?
      URI.parse(url)
    rescue URI::Error
      nil
    end

    private def self.dangerous_host?(host : String?) : Bool
      host = normalize_host(host)
      return true if host.nil? || host.empty?
      return true if localhost_like?(host)
      return true if private_ip_range?(host)
      return true if host.ends_with?(".local")
      return true if resolves_to_private_ip?(host)
      false
    end

    # Normalize hostnames for validation: strip trailing dot and downcase
    private def self.normalize_host(host : String?) : String?
      if host
        h = host.strip
        # Strip a trailing dot (e.g. "localhost.") which is equivalent to
        # the same hostname without the dot.
        h = h[0..-2] if h.ends_with?('.') && h.size > 1
        h.downcase
      end
    end

    # Detect if a host string is a literal IP (IPv4 dotted or IPv6-like)
    private def self.literal_ip_string?(host : String) : Bool
      return true if host =~ /^\d{1,3}(?:\.\d{1,3}){3}$/ # IPv4 dotted
      return true if host.includes?(":")                 # IPv6 or other colon forms
      false
    end

    private def self.localhost_like?(host : String) : Bool
      host.downcase == "localhost" ||
        host == "0.0.0.0" ||
        host == "[::1]" ||
        host == "::1"
    end

    private def self.private_ip_range?(host : String) : Bool
      return false unless literal_ip_string?(host)
      private_ip?(host)
    end
  end
end
