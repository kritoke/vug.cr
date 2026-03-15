require "uri"

module Vug
  # Validates URLs to prevent SSRF (Server-Side Request Forgery) attacks
  # Blocks requests to private IP ranges, localhost, and other dangerous destinations
  module UrlValidator
    # Check if an IP address string matches private ranges
    def self.private_ip?(ip : String) : Bool
      return true if ip.starts_with?("127.")     # localhost
      return true if ip == "0.0.0.0"             # unspecified
      return true if ip.starts_with?("10.")      # RFC 1918 Class A
      return true if ip.starts_with?("192.168.") # RFC 1918 Class C

      # IPv6
      return true if ip == "::1"                                    # IPv6 localhost
      return true if ip.starts_with?("fc") || ip.starts_with?("fd") # unique local
      return true if ip.starts_with?("fe80:")                       # link-local
      return true if ip.includes?("::ffff:")                        # IPv4-mapped IPv6

      false
    end

    def self.valid_url?(url : String) : Bool
      begin
        uri = URI.parse(url)
        return false unless valid_scheme?(uri.scheme)
        return false if dangerous_host?(uri.host)
        true
      rescue
        false
      end
    end

    def self.valid_redirect_url?(original_url : String, redirect_url : String) : Bool
      # Validate both original and redirect URLs
      return false unless valid_url?(original_url)
      return false unless valid_url?(redirect_url)

      # Additional check: ensure redirect doesn't change scheme in dangerous ways
      original_uri = URI.parse(original_url)
      redirect_uri = URI.parse(redirect_url)

      # Allow HTTPS -> HTTP redirects only if explicitly configured (not by default)
      # For now, be conservative and block scheme downgrades
      if original_uri.scheme == "https" && redirect_uri.scheme == "http"
        return false
      end

      true
    end

    private def self.valid_scheme?(scheme : String?) : Bool
      return false if scheme.nil?
      ["http", "https"].includes?(scheme.downcase)
    end

    private def self.dangerous_host?(host : String?) : Bool
      return true if host.nil? || host.empty?

      # Check for localhost variants
      if host.downcase == "localhost" ||
         host == "0.0.0.0" ||
         host == "[::1]" ||
         host == "::1"
        return true
      end

      # Check if host looks like an IP address
      if host.includes?(".") || host.includes?(":")
        # Try to validate as IP
        if private_ip?(host)
          return true
        end
        # For IPv4 addresses in 172.16-31.x.x range (RFC 1918 Class B)
        if host.starts_with?("172.")
          parts = host.split('.')
          if parts.size == 4
            second_octet = parts[1].to_i?
            if second_octet && (16..31).includes?(second_octet)
              return true
            end
          end
        end
      end

      # Allow domain names - they will be resolved by the HTTP client
      # which should have its own protections
      false
    end
  end
end
