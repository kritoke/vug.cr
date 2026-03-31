require "uri"
require "socket"

module Vug
  # Validates URLs to prevent SSRF (Server-Side Request Forgery) attacks
  # Blocks requests to private IP ranges, localhost, and other dangerous destinations
  module UrlValidator
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
    rescue
      false
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
        rescue
          ch.send(true)
        end
      end

      select
      when blocked = ch.receive
        blocked
      when timeout(5.seconds)
        true
      end
    rescue
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
