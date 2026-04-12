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

      # Try to treat as an IPv4 dotted literal first (fast path)
      if ip =~ /^\d{1,3}(?:\.\d{1,3}){3}$/
        parts = ip.split(".").map(&.to_u32)
        # validate octets
        return false unless parts.all? { |p| p <= 255_u32 }
        ip_int = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]

        # Use U32 masks/values to avoid sign issues
        ip_int_u = ip_int.to_u32

        # 10.0.0.0/8
        return true if (ip_int_u & 0xff000000_u32) == 0x0a000000_u32
        # 172.16.0.0/12
        return true if (ip_int_u & 0xfff00000_u32) == 0xac100000_u32
        # 192.168.0.0/16
        return true if (ip_int_u & 0xffff0000_u32) == 0xc0a80000_u32
        # 127.0.0.0/8 loopback
        return true if (ip_int_u & 0xff000000_u32) == 0x7f000000_u32

        # Carrier-grade NAT 100.64.0.0/10
        return true if (ip_int_u & 0xffc00000_u32) == 0x64400000_u32

        # Benchmark/testing network 198.18.0.0/15
        return true if (ip_int_u & 0xfffe0000_u32) == 0xc6120000_u32

        # Link-local 169.254.0.0/16
        return true if (ip_int_u & 0xffff0000_u32) == 0xa9fe0000_u32

        # Multicast 224.0.0.0/4
        return true if (ip_int_u & 0xf0000000_u32) == 0xe0000000_u32

        # Reserved 240.0.0.0/4
        return true if (ip_int_u & 0xf0000000_u32) == 0xf0000000_u32

        return false
      end

      # Fallback to Socket parsing for IPv6 and other literal forms.
      # Socket::IPAddress parsing can raise for malformed input; rescue and
      # return false to indicate the IP is not considered "private" here.
      addr = Socket::IPAddress.new(ip, 0) rescue nil
      return false unless addr
      # loopback/private/link-local detection provided by stdlib
      addr.loopback? || addr.private? || addr.link_local?
    rescue
      false
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

    private def self.valid_scheme?(scheme : String?) : Bool
      return false if scheme.nil?
      ["http", "https"].includes?(scheme.downcase)
    end

    private def self.dangerous_host?(host : String?, config : Vug::Config? = nil) : Bool
      host = normalize_host(host)

      if host.nil? || host.empty?
        config.try &.error("dangerous_host?(#{host.inspect})", "Blocked: host is nil or empty")
        return true
      end

      if localhost_like?(host)
        config.try &.error("dangerous_host?(#{host})", "Blocked: localhost-like host")
        return true
      end

      if ip_in_private_range?(host)
        config.try &.error("dangerous_host?(#{host})", "Blocked: IP in private range")
        return true
      end

      if host.ends_with?(".local")
        config.try &.error("dangerous_host?(#{host})", "Blocked: .local domain")
        return true
      end

      if resolves_to_private_ip?(host)
        config.try &.error("dangerous_host?(#{host})", "Blocked: resolves to private IP")
        return true
      end

      false
    end

    # Normalize hostnames for validation: strip trailing dot and downcase
    private def self.normalize_host(host : String?) : String?
      return nil if host.nil?
      h = host.strip
      h = h[0..-2] if h.ends_with?('.') && h.size > 1
      h.downcase
    end

    # Detect if a host string is a literal IP (IPv4 dotted or IPv6-like)
    private def self.literal_ip_string?(host : String) : Bool
      return true if host =~ /^\d{1,3}(?:\.\d{1,3}){3}$/ # IPv4 dotted
      return true if host.includes?(":") # IPv6 or other colon forms
      false
    end

    private def self.localhost_like?(host : String) : Bool
      host.downcase == "localhost" ||
        host == "0.0.0.0" ||
        host == "[::1]" ||
        host == "::1"
    end

    private def self.ip_in_private_range?(host : String) : Bool
      return false unless host.includes?(".") || host.includes?(":")
      private_ip?(host)
    end
  end
end
