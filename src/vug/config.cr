require "time"

module Vug
  # Configuration for Vug favicon fetching.
  #
  # NOTE: This is a class rather than a record because it contains Proc callbacks
  # (on_save, on_load, on_debug, etc.) which are not comparable and cannot be used
  # in Crystal records. If callback support is ever removed, consider converting
  # to a record to gain automatic `copy_with` support.
  class Config
    DEFAULT_USER_AGENT      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    DEFAULT_ACCEPT_LANGUAGE = "en-US,en;q=0.9"

    getter timeout : Time::Span = 30.seconds
    getter connect_timeout : Time::Span = 10.seconds
    getter max_redirects : Int32 = 10
    getter max_size : Int32 = 100 * 1024
    getter user_agent : String = DEFAULT_USER_AGENT
    getter accept_language : String = DEFAULT_ACCEPT_LANGUAGE

    getter cache_size_limit : Int32 = 10 * 1024 * 1024
    getter cache_entry_ttl : Time::Span = 7.days

    # Google SVG placeholders are exactly 198 bytes when fetched from google.com/s2/favicons.
    # Detecting this size allows us to fall back to a larger resolution.
    getter gray_placeholder_size : Int32 = 198

    getter max_concurrent_requests : Int32 = 8
    getter? image_validation_hard : Bool = false

    getter on_save : Proc(String, Bytes, String, String?)? = nil
    getter on_load : Proc(String, String?)? = nil
    getter on_debug : Proc(String, Nil)? = nil
    getter on_error : Proc(String, String, Nil)? = nil
    getter on_warning : Proc(String, Nil)? = nil

    DEFAULT = Config.new

    def self.default : Config
      DEFAULT
    end

    def initialize(
      timeout : Time::Span? = nil,
      connect_timeout : Time::Span? = nil,
      max_redirects : Int32? = nil,
      max_size : Int32? = nil,
      user_agent : String? = nil,
      accept_language : String? = nil,
      cache_size_limit : Int32? = nil,
      cache_entry_ttl : Time::Span? = nil,
      gray_placeholder_size : Int32? = nil,
      max_concurrent_requests : Int32? = nil,
      on_save : Proc(String, Bytes, String, String?)? = nil,
      on_load : Proc(String, String?)? = nil,
      on_debug : Proc(String, Nil)? = nil,
      on_error : Proc(String, String, Nil)? = nil,
      on_warning : Proc(String, Nil)? = nil,
    )
      @timeout = validate_positive_timespan(timeout, "timeout", 30.seconds)
      @connect_timeout = validate_positive_timespan(connect_timeout, "connect_timeout", 10.seconds)
      @max_redirects = validate_non_negative_int(max_redirects, "max_redirects", 10)
      @max_size = validate_positive_int(max_size, "max_size", 100 * 1024)
      @cache_size_limit = validate_positive_int(cache_size_limit, "cache_size_limit", 10 * 1024 * 1024)
      @cache_entry_ttl = validate_positive_timespan(cache_entry_ttl, "cache_entry_ttl", 7.days)
      @gray_placeholder_size = validate_non_negative_int(gray_placeholder_size, "gray_placeholder_size", 198)
      @max_concurrent_requests = validate_positive_int(max_concurrent_requests, "max_concurrent_requests", 8)

      @user_agent = user_agent || DEFAULT_USER_AGENT
      @accept_language = accept_language || DEFAULT_ACCEPT_LANGUAGE
      @on_save = on_save
      @on_load = on_load
      @on_debug = on_debug
      @on_error = on_error
      @on_warning = on_warning
    end

    private def validate_positive_timespan(value : Time::Span?, name : String, default : Time::Span) : Time::Span
      if value
        raise ArgumentError.new("#{name} must be positive") if value <= 0.seconds
        value
      else
        default
      end
    end

    private def validate_positive_int(value : Int32?, name : String, default : Int32) : Int32
      if value
        raise ArgumentError.new("#{name} must be positive") if value <= 0
        value
      else
        default
      end
    end

    private def validate_non_negative_int(value : Int32?, name : String, default : Int32) : Int32
      if value
        raise ArgumentError.new("#{name} must be non-negative") if value < 0
        value
      else
        default
      end
    end

    def debug(message : String) : Nil
      @on_debug.try(&.call(message))
    end

    def error(context : String, message : String) : Nil
      @on_error.try(&.call(context, message))
    end

    def warning(message : String) : Nil
      @on_warning.try(&.call(message))
    end

    def save(url : String, data : Bytes, content_type : String) : String?
      @on_save.try(&.call(url, data, content_type))
    end

    def load(url : String) : String?
      @on_load.try(&.call(url))
    end

    def has_storage? : Bool
      !@on_save.nil?
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def copy_with(
      timeout : Time::Span? = nil,
      connect_timeout : Time::Span? = nil,
      max_redirects : Int32? = nil,
      max_size : Int32? = nil,
      user_agent : String? = nil,
      accept_language : String? = nil,
      cache_size_limit : Int32? = nil,
      cache_entry_ttl : Time::Span? = nil,
      gray_placeholder_size : Int32? = nil,
      max_concurrent_requests : Int32? = nil,
      on_save : Proc(String, Bytes, String, String?)? = nil,
      on_load : Proc(String, String?)? = nil,
      on_debug : Proc(String, Nil)? = nil,
      on_error : Proc(String, String, Nil)? = nil,
      on_warning : Proc(String, Nil)? = nil,
    ) : Config
      Config.new(
        timeout: timeout || @timeout,
        connect_timeout: connect_timeout || @connect_timeout,
        max_redirects: max_redirects || @max_redirects,
        max_size: max_size || @max_size,
        user_agent: user_agent || @user_agent,
        accept_language: accept_language || @accept_language,
        cache_size_limit: cache_size_limit || @cache_size_limit,
        cache_entry_ttl: cache_entry_ttl || @cache_entry_ttl,
        gray_placeholder_size: gray_placeholder_size || @gray_placeholder_size,
        max_concurrent_requests: max_concurrent_requests || @max_concurrent_requests,
        on_save: on_save || @on_save,
        on_load: on_load || @on_load,
        on_debug: on_debug || @on_debug,
        on_error: on_error || @on_error,
        on_warning: on_warning || @on_warning,
      )
    end
  end
end
