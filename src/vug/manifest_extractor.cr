require "json"
require "http/client"
require "uri"
require "./config"
require "./types"

module Vug
  # Represents a favicon entry from HTML, manifest, or other sources
  record FaviconInfo,
    url : String,
    sizes : String?,
    type : String?,
    purpose : String? do
    def size_pixels : Int32?
      return if sizes.nil? || sizes == "any"

      # Handle multiple sizes like "16x16 32x32" - take the largest
      size_list = sizes.split(' ')
      max_size = 0

      size_list.each do |size_str|
        if size_str.includes?('x')
          parts = size_str.split('x')
          if parts.size == 2
            begin
              width = parts[0].to_i
              height = parts[1].to_i
              area = width * height
              max_size = [max_size, area].max
            rescue
              # Skip invalid size format
            end
          end
        end
      end

      max_size > 0 ? max_size : nil
    end

    def has_any_size? : Bool
      sizes == "any"
    end
  end

  class ManifestExtractor
    @config : Config

    def initialize(@config : Config)
    end

    def extract_manifest_url(html_content : String, base_url : String) : String?
      parser = Lexbor.new(html_content)
      nodes = parser.css("link[rel='manifest']")

      nodes.each do |node|
        href = node["href"]?
        next if href.nil? || href.empty?

        normalized = normalize_url(href, base_url)
        return normalized if valid_scheme?(normalized)
      end

      nil
    end

    def extract_favicons_from_manifest(manifest_url : String) : Array(FaviconInfo)?
      @config.debug("Fetching manifest: #{manifest_url}")

      begin
        uri = URI.parse(manifest_url)
        client = create_client(uri)

        headers = HTTP::Headers{
          "User-Agent" => @config.user_agent,
          "Accept"     => "application/manifest+json,application/json,*/*;q=0.8",
        }

        client.get(uri.request_target, headers: headers) do |response|
          if response.status.success?
            memory = IO::Memory.new
            IO.copy(response.body_io, memory, limit: @config.max_size)
            json_content = memory.to_slice.to_s

            manifest = JSON.parse(json_content)
            return parse_manifest_icons(manifest, manifest_url)
          else
            @config.debug("Manifest fetch failed #{response.status_code}: #{manifest_url}")
            return
          end
        end
      rescue ex
        @config.error("extract_favicons_from_manifest(#{manifest_url})", ex)
        @config.debug("Error fetching manifest: #{ex.message}")
      end
    end

    private def parse_manifest_icons(manifest : JSON::Any, manifest_url : String) : Array(FaviconInfo)
      icons = [] of FaviconInfo

      if manifest["icons"]? && manifest["icons"].as_a?
        manifest["icons"].as_a.each do |icon_json|
          if icon_json.is_a?(JSON::Any) && icon_json.as_h?
            icon_data = icon_json.as_h
            if icon_data["src"]?
              src = icon_data["src"].as_s
              normalized_src = normalize_url(src, manifest_url)

              favicon_info = FaviconInfo.new(
                url: normalized_src,
                sizes: icon_data["sizes"]?.try(&.as_s),
                type: icon_data["type"]?.try(&.as_s),
                purpose: icon_data["purpose"]?.try(&.as_s)
              )
              icons << favicon_info
            end
          end
        end
      end

      icons
    end

    private def normalize_url(url : String, base_url : String) : String
      if url.starts_with?("//")
        "https:#{url}"
      elsif !url.starts_with?("http")
        resolved = resolve_url(url.strip, base_url)
        return resolved if valid_scheme?(resolved)
        url
      else
        url
      end
    end

    private def valid_scheme?(url : String) : Bool
      !(url.starts_with?("javascript:") ||
        url.starts_with?("data:") ||
        url.starts_with?("vbscript:"))
    end

    private def resolve_url(url : String, base : String) : String
      URI.parse(base).resolve(url.strip).to_s
    rescue
      url
    end

    private def create_client(uri : URI) : HTTP::Client
      client = HTTP::Client.new(uri)
      client.compress = true
      client.read_timeout = @config.timeout
      client.connect_timeout = @config.connect_timeout
      client
    end
  end
end
