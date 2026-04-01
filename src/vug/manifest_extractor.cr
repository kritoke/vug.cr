require "json"
require "http/client"
require "uri"
require "html5"
require "./config"
require "./url_validator"
require "./types"
require "./favicon_info"

module Vug
  class ManifestExtractor
    def initialize(@config : Config, http_client_factory : HttpClientFactory? = nil)
      @http_client_factory = http_client_factory || HttpClientFactory.new(@config)
    end

    def extract_manifest_url(html_content : String, base_url : String) : String?
      doc = HTML5.parse(html_content)
      nodes = doc.css("link[rel='manifest']")

      nodes.each do |node|
        href_attr = node["href"]?
        next if href_attr.nil?
        href = href_attr.val
        next if href.empty?

        # Handle relative URLs by resolving against base_url first
        normalized = UrlProcessor.resolve_and_normalize(href, base_url)
        return normalized if UrlProcessor.valid_scheme?(normalized)
      end

      nil
    end

    def extract_favicons_from_manifest(manifest_url : String) : Array(FaviconInfo)?
      unless UrlValidator.valid_url?(manifest_url)
        @config.debug("Manifest URL blocked by validator: #{manifest_url}")
        return
      end

      @config.debug("Fetching manifest: #{manifest_url}")

      begin
        uri = URI.parse(manifest_url)
        client = @http_client_factory.create_client(uri)

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
      rescue IO::TimeoutError
        @config.error("extract_favicons_from_manifest(#{manifest_url})", "Read timed out")
        @config.debug("Manifest fetch timeout: #{manifest_url}")
      rescue ex : JSON::ParseException | IO::Error | Socket::Error
        @config.error("extract_favicons_from_manifest(#{manifest_url})", ex.message || "Unknown error")
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
              # Handle relative URLs by resolving against manifest_url first
              normalized_src = UrlProcessor.resolve_and_normalize(src, manifest_url)

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
  end
end
