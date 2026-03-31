require "uri"
require "socket"

module Vug
  # Validates URLs to prevent SSRF (Server-Side Request Forgery) attacks
  # Blocks requests to private IP ranges, localhost, and other dangerous destinations
  module UrlValidator
    DNS_CACHE_TTL = 30.seconds

    # DNS cache: hostname -> {resolved_ips, timestamp}
    @@dns_cache = Hash(String, {Array(String), Time::Span}).new
    @@dns_cache_mutex = Mutex.new

    # Check if an IP address string matches private ranges
    def self.private_ip?(ip : String) : Bool
      return true if ip.starts_with?("127.")                         # localhost
      return true if ip == "0.0.0.0"                                 # unspecified
      return true if ip.starts_with?("10.")                          # RFC 1918 Class A (10.0.0.0/8)
      return true if ip.starts_with?("172.") && private_class_b?(ip) # RFC 1918 Class B (172.16.0.0/12)
      return true if ip.starts_with?("192.168.")                     # RFC 1918 Class C (192.168.0.0/16)

      # IPv6
      return true if ip == "::1"                                    # IPv6 localhost
      return true if ip.starts_with?("fc") || ip.starts_with?("fd") # IPv6 unique local (fc00::/7)
      return true if ip.starts_with?("fe80:")                       # IPv6 link-local
      return true if ip.includes?("::ffff:")                        # IPv4-mapped IPv6

      false
    end

    def self.valid_url?(url : String) : Bool
      uri = URI.parse(url)
      return false unless valid_scheme?(uri.scheme)
      return false if dangerous_host?(uri.hostname)
      true
    rescue URI::Error
      false
    end

    # Re-validate a URL's DNS resolution before making an HTTP request.
    # Returns false if the DNS resolution differs from the cached validation
    # (possible DNS rebinding attack) or if any resolved IP is private.
    def self.revalidate_url?(url : String) : Bool
      uri = URI.parse(url)
      host = uri.hostname
      return false if host.nil? || host.empty?
      return true if localhost_like?(host)

      # If host is a raw IP, check it directly
      if host.includes?(".") || host.includes?(":")
        return !private_ip?(host)
      end

      # Resolve fresh and check if any result is a private IP
      ips = resolve_ips_cached(host)
      return false if ips.empty?

      !ips.any? { |ip| private_ip?(ip) }
    rescue URI::Error
      false
    end

    # Resolve a hostname to a list of IP strings, using the DNS cache.
    def self.resolve_ips_cached(host : String) : Array(String)
      @@dns_cache_mutex.synchronize do
        if entry = @@dns_cache[host]?
          ips, timestamp = entry
          if Time.monotonic - timestamp < DNS_CACHE_TTL
            return ips
          end
        end
      end

      ips = resolve_ips_uncached(host)

      @@dns_cache_mutex.synchronize do
        @@dns_cache[host] = {ips, Time.monotonic}
      end

      ips
    end

    private def self.resolve_ips_uncached(host : String) : Array(String)
      addrinfos = Socket::Addrinfo.resolve(host, "80", type: Socket::Type::STREAM)
      addrinfos.compact_map { |addrinfo| addrinfo.ip_address.try(&.to_s) }
    rescue Socket::Addrinfo::Error
      [] of String
    end

    # Clear the DNS cache (useful for testing)
    def self.clear_dns_cache : Nil
      @@dns_cache_mutex.synchronize { @@dns_cache.clear }
    end

    private def self.valid_scheme?(scheme : String?) : Bool
      return false if scheme.nil?
      ["http", "https"].includes?(scheme.downcase)
    end

    private def self.dangerous_host?(host : String?) : Bool
      return true if host.nil? || host.empty?

      return true if localhost_like?(host)
      return true if ip_in_private_range?(host)
      return true if host.ends_with?(".local")

      return true if resolves_to_private_ip?(host)

      false
    end

    def self.resolves_to_private_ip?(host : String) : Bool
      return private_ip?(host) if host.includes?(".") || host.includes?(":")

      ch = Channel(Bool).new

      spawn do
        begin
          addrinfos = Socket::Addrinfo.resolve(host, "80", type: Socket::Type::STREAM)
          blocked = addrinfos.any? do |addrinfo|
            if ip = addrinfo.ip_address
              private_ip?(ip.to_s)
            else
              false
            end
          end
          ch.send(blocked)
        rescue Socket::Addrinfo::Error
          ch.send(true)
        end
      end

      select
      when blocked = ch.receive
        blocked
      when timeout(5.seconds)
        true
      end
    rescue Channel::ClosedError
      true
    end

    private def self.localhost_like?(host : String) : Bool
      host.downcase == "localhost" ||
        host == "0.0.0.0" ||
        host == "[::1]" ||
        host == "::1"
    end

    private def self.ip_in_private_range?(host : String) : Bool
      return false unless host.includes?(".") || host.includes?(":")

      return true if private_ip?(host)
      return true if private_class_b?(host)

      false
    end

    private def self.private_class_b?(host : String) : Bool
      return false unless host.starts_with?("172.")

      parts = host.split('.')
      return false unless parts.size == 4

      second_octet = parts[1].to_i?
      return false unless second_octet

      (16..31).includes?(second_octet)
    end
  end
end
