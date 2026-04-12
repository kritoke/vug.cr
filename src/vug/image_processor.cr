require "./cache_manager"
require "./types"
require "./image_validator"

module Vug
  class ImageProcessor
    def initialize(@config : Config); end

    # Process a bytes blob and return a Vug::Result
    def process_bytes(url : String, data : Bytes, content_type : String) : Result
      Vug.failure("not_implemented", url, error_type: :fetch_error)
    end
  end

  class ImageProcessor::Default < ImageProcessor
    # declare typed instance var to avoid inference issues
    @cache_manager : CacheManager?

    def initialize(config : Config, cache_manager : CacheManager? = nil)
      super(config)
      @cache_manager = cache_manager
    end

    def process_bytes(url : String, data : Bytes, content_type : String) : Result
      if data.empty?
        @config.debug("Empty favicon response: #{url}")
        return Vug.failure("Empty response", url, error_type: :empty_response)
      end

      unless ImageValidator.valid?(data, @config.image_validation_hard?)
        @config.debug("Invalid favicon content (not an image): #{url}")
        return Vug.failure("Invalid image", url, error_type: :invalid_image)
      end

      if dims = ImageValidator.get_image_dimensions(data)
        width, height = dims
        @config.debug("Favicon fetched: #{url}, size=#{data.size}, type=#{content_type} (#{width}x#{height})")
      else
        @config.debug("Favicon fetched: #{url}, size=#{data.size}, type=#{content_type}")
      end

      if saved_path = @config.save(url, data, content_type)
        @config.debug("Favicon saved: #{saved_path}")
        @cache_manager.try(&.set(url, saved_path))
        Vug.success(url, saved_path, content_type, data)
      else
        @config.debug("Favicon save failed: #{url}")
        Vug.failure("Save failed", url, error_type: :save_failed)
      end
    end
  end
end
