require "http/client"
require "uri"
require "html5"
require "sanitize"
require "digest"
require "./config"
require "./url_validator"
require "./types"
require "./manifest_extractor"
require "./data_url_handler"

module Vug
  class HtmlExtractor
    FAVICON_SELECTORS = [
      "link[rel~='icon']",
      "link[rel='shortcut icon']",
      "link[rel='apple-touch-icon']",
      "link[rel='apple-touch-icon-precomposed']",
      "link[type='image/x-icon']",
    ]

    def initialize(@config : Config = Config.new, manifest_extractor : ManifestExtractor? = nil, http_client_factory : HttpClientFactory? = nil)
      @manifest_extractor = manifest_extractor || ManifestExtractor.new(@config)
      @http_client_factory = http_client_factory || HttpClientFactory.new(@config)
    end

    def extract_all(site_url : String) : Array(FaviconInfo)
      clean_url = UrlProcessor.sanitize_feed_url(site_url)

      # Validate URL has a scheme and is not dangerous before attempting HTTP request
      begin
        unless UrlValidator.valid_url?(clean_url)
          @config.debug("URL blocked by validator: #{clean_url}")
          return [] of FaviconInfo
        end

        uri = URI.parse(clean_url)
        unless uri.scheme
          @config.debug("URL missing scheme: #{clean_url}")
          return [] of FaviconInfo
        end
      rescue ex
        @config.debug("Invalid URL for HTML extraction: #{clean_url} - #{ex.message}")
        return [] of FaviconInfo
      end

      favicons = [] of FaviconInfo

      begin
        @config.debug("Fetching HTML from: #{clean_url}")

        uri = URI.parse(clean_url)
        client = @http_client_factory.create_client(uri)

        headers = HTTP::Headers{
          "User-Agent" => @config.user_agent,
          "Accept"     => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        }

        client.get(uri.request_target, headers: headers) do |response|
          if response.status.success?
            memory = IO::Memory.new
            IO.copy(response.body_io, memory, limit: @config.max_size)
            html = memory.to_slice.to_s
            @config.debug("HTML fetched: #{html.size} bytes")

            html = sanitize_html(html)
            @config.debug("HTML sanitized: #{html.size} bytes")

            # Extract favicons from HTML
            html_favicons = extract_favicons_from_html(html, clean_url)
            favicons.concat(html_favicons)

            # Extract manifest URL and parse manifest favicons
            if manifest_url = @manifest_extractor.extract_manifest_url(html, clean_url)
              @config.debug("Found manifest: #{manifest_url}")
              if manifest_favicons = @manifest_extractor.extract_favicons_from_manifest(manifest_url)
                favicons.concat(manifest_favicons)
                @config.debug("Extracted #{manifest_favicons.size} favicons from manifest")
              end
            end
          elsif response.status.not_found?
            @config.debug("HTML fetch 404: #{clean_url}")
          else
            @config.debug("HTML fetch error #{response.status_code}: #{clean_url}")
          end
        end
      rescue Socket::Addrinfo::Error
        @config.debug("DNS lookup failed for: #{site_url}")
      rescue IO::TimeoutError
        @config.error("extract_all(#{site_url})", "Read timed out")
        @config.debug("HTML fetch timeout: #{site_url}")
      rescue ex
        @config.error("extract_all(#{site_url})", ex.message || "Unknown error")
        @config.debug("Error extracting favicons: #{ex.message}")
      end

      favicons
    end

    # Backward compatibility method - returns first favicon only
    def extract(site_url : String) : String?
      favicons = extract_all(site_url)
      return favicons.first?.try(&.url) if !favicons.empty?
      nil
    end

    private def extract_favicons_from_html(html : String, base_url : String) : Array(FaviconInfo)
      favicons = [] of FaviconInfo
      doc = HTML5.parse(html)

      FAVICON_SELECTORS.each do |selector|
        nodes = doc.css(selector)
        next if nodes.empty?

        nodes.each do |node|
          href_attr = node["href"]?
          next if href_attr.nil?
          href = href_attr.val
          next if href.empty?

          # Handle data URLs specially
          if DataUrlHandler.data_url?(href)
            if data_result = DataUrlHandler.extract_from_url(href)
              data, media_type = data_result
              # Create a temporary URL identifier for data URLs
              data_url_id = "data:#{Digest::SHA256.hexdigest(data.to_slice)}"
              favicon_info = FaviconInfo.new(
                url: data_url_id,
                sizes: node["sizes"]?.try(&.val),
                type: media_type,
                purpose: nil
              )
              # Store the actual data in the favicon info for later use
              @config.debug("Found data URL favicon: #{data_url_id}")
              favicons << favicon_info

              # Also save the data immediately since it's already available
              if saved_path = @config.save(data_url_id, data, media_type)
                @config.debug("Data URL favicon saved: #{saved_path}")
              end
            else
              @config.debug("Invalid data URL favicon: #{href}")
            end
          else
            # Handle relative URLs by resolving against base_url first
            if !href.starts_with?("http")
              resolved = UrlProcessor.resolve_url(href.strip, base_url)
              normalized = UrlProcessor.normalize_url(resolved, "https")
            else
              normalized = UrlProcessor.normalize_url(href, "https")
            end
            next unless UrlProcessor.valid_scheme?(normalized)

            sizes = node["sizes"]?.try(&.val)
            type = node["type"]?.try(&.val)

            favicon_info = FaviconInfo.new(
              url: normalized,
              sizes: sizes,
              type: type,
              purpose: nil
            )
            favicons << favicon_info
          end
        end
      end

      favicons
    end

    private def sanitize_html(html : String) : String
      Sanitize::Policy::HTMLSanitizer.common.process(html)
    rescue
      html
    end
  end
end
