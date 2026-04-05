require "uri"
require "socket"
require "./dns_cache"

module Vug
  module UrlValidator
    def self.private_ip?(ip : String) : Bool
      return true if ip == "0.0.0.0"
      if ip.starts_with?("::ffff:")
        ipv4_part = ip.split("::ffff:")[1]?
        return private_ip?(ipv4_part) if ipv4_part
      end
      addr = Socket::IPAddress.new(ip, 0) rescue nil
      return false unless addr
      addr.loopback? || addr.private? || addr.link_local?
    rescue
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

    def self.revalidate_url?(url : String) : Bool
      uri = URI.parse(url)
      host = uri.hostname
      return false if host.nil? || host.empty?
      return true if localhost_like?(host)

      if host.includes?(".") || host.includes?(":")
        return !private_ip?(host)
      end

      ips = DnsCache.resolve(host)
      return false if ips.empty?

      !ips.any? { |ip| private_ip?(ip) }
    rescue URI::Error
      false
    end

    def self.resolves_to_private_ip?(host : String) : Bool
      return private_ip?(host) if host.includes?(".") || host.includes?(":")

      ips = DnsCache.resolve(host)
      return true if ips.empty?

      ips.any? { |ip| private_ip?(ip) }
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
