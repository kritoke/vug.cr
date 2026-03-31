require "uri"
require "socket"
require "./dns_cache"

module Vug
  module UrlValidator
    def self.private_ip?(ip : String) : Bool
      return true if ip.starts_with?("127.")
      return true if ip == "0.0.0.0"
      return true if ip.starts_with?("10.")
      return true if ip.starts_with?("172.") && private_class_b?(ip)
      return true if ip.starts_with?("192.168.")
      return true if ip == "::1"
      return true if ip.starts_with?("fc") || ip.starts_with?("fd")
      return true if ip.starts_with?("fe80:")
      return true if ip.includes?("::ffff:")
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
