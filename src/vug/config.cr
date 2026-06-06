require "time"
require "./log_entry"

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

    # Google favicon API returns a 198-byte SVG placeholder when no
    # real favicon exists for a domain.
    GOOGLE_PLACEHOLDER_SIZE = 198

    getter timeout : Time::Span = 30.seconds
    getter html_fetch_timeout : Time::Span = 60.seconds # Longer timeout for HTML page fetches
    getter connect_timeout : Time::Span = 10.seconds
    getter write_timeout : Time::Span = 10.seconds
    getter max_redirects : Int32 = 10
    getter max_size : Int32 = 100 * 1024
    getter user_agent : String = DEFAULT_USER_AGENT
    getter accept_language : String = DEFAULT_ACCEPT_LANGUAGE

    getter cache_size_limit : Int32 = 10 * 1024 * 1024
    getter cache_entry_ttl : Time::Span = 7.days

    # Google SVG placeholders are exactly 198 bytes when fetched from google.com/s2/favicons.
    # Detecting this size allows us to fall back to a larger resolution.
    getter gray_placeholder_size : Int32 = GOOGLE_PLACEHOLDER_SIZE

    # NOTE: This setting controls the process-wide semaphore limit.
    # Only the first-initialized value takes effect; subsequent Fetcher
    # instances with different values will share the existing semaphore.
    getter max_concurrent_requests : Int32 = 8
    getter? image_validation_hard : Bool = false

    # Retry settings for transient failures (timeouts, socket errors, etc.)
    getter max_retries : Int32 = 2
    getter retry_base_delay : Time::Span = 500.milliseconds
    getter retry_max_delay : Time::Span = 5.seconds

    getter on_save : Proc(String, Bytes, String, String?)? = nil
    getter on_load : Proc(String, String?)? = nil
    getter on_debug : Proc(String, Nil)? = nil
    getter on_error : Proc(String, String, Nil)? = nil
    getter on_warning : Proc(String, Nil)? = nil

    # Optional structured logging callback. When set, receives LogEntry
    # objects alongside the existing level-specific callbacks.
    getter on_log : Proc(LogEntry, Nil)? = nil

    DEFAULT = Config.new

    def self.default : Config
      DEFAULT
    end

    def initialize(
      timeout : Time::Span? = nil,
      html_fetch_timeout : Time::Span? = nil,
      connect_timeout : Time::Span? = nil,
      write_timeout : Time::Span? = nil,
      max_redirects : Int32? = nil,
      max_size : Int32? = nil,
      user_agent : String? = nil,
      accept_language : String? = nil,
      cache_size_limit : Int32? = nil,
      cache_entry_ttl : Time::Span? = nil,
      gray_placeholder_size : Int32? = nil,
      max_concurrent_requests : Int32? = nil,
      max_retries : Int32? = nil,
      retry_base_delay : Time::Span? = nil,
      retry_max_delay : Time::Span? = nil,
      on_save : Proc(String, Bytes, String, String?)? = nil,
      on_load : Proc(String, String?)? = nil,
      on_debug : Proc(String, Nil)? = nil,
      on_error : Proc(String, String, Nil)? = nil,
      on_warning : Proc(String, Nil)? = nil,
      on_log : Proc(LogEntry, Nil)? = nil,
    )
      @timeout = validate_positive_timespan(timeout, "timeout", 30.seconds)
      @html_fetch_timeout = validate_positive_timespan(html_fetch_timeout, "html_fetch_timeout", 60.seconds)
      @connect_timeout = validate_positive_timespan(connect_timeout, "connect_timeout", 10.seconds)
      @write_timeout = validate_positive_timespan(write_timeout, "write_timeout", 10.seconds)
      @max_redirects = validate_non_negative(max_redirects, "max_redirects", 10)
      @max_size = validate_positive_int(max_size, "max_size", 100 * 1024)
      @cache_size_limit = validate_positive_int(cache_size_limit, "cache_size_limit", 10 * 1024 * 1024)
      @cache_entry_ttl = validate_positive_timespan(cache_entry_ttl, "cache_entry_ttl", 7.days)
      @gray_placeholder_size = validate_non_negative(gray_placeholder_size, "gray_placeholder_size", GOOGLE_PLACEHOLDER_SIZE)
      @max_concurrent_requests = validate_positive_int(max_concurrent_requests, "max_concurrent_requests", 8)
      @max_retries = validate_non_negative(max_retries, "max_retries", 2)
      @retry_base_delay = validate_positive_timespan(retry_base_delay, "retry_base_delay", 500.milliseconds)
      @retry_max_delay = validate_positive_timespan(retry_max_delay, "retry_max_delay", 5.seconds)

      @user_agent = user_agent || DEFAULT_USER_AGENT
      @accept_language = accept_language || DEFAULT_ACCEPT_LANGUAGE
      @on_save = on_save
      @on_load = on_load
      @on_debug = on_debug
      @on_error = on_error
      @on_warning = on_warning
      @on_log = on_log
    end

    private def validate_positive_timespan(value : Time::Span?, name : String, default : Time::Span) : Time::Span
      return default unless value
      raise ArgumentError.new("#{name} must be positive") if value <= 0.seconds
      value
    end

    private def validate_positive_int(value : Int32?, name : String, default : Int32) : Int32
      return default unless value
      raise ArgumentError.new("#{name} must be positive") if value <= 0
      value
    end

    private def validate_non_negative(value : Int32?, name : String, default : Int32) : Int32
      return default unless value
      raise ArgumentError.new("#{name} must be non-negative") if value < 0
      value
    end

    def debug(message : String) : Nil
      @on_debug.try(&.call(message))
      @on_log.try(&.call(LogEntry.new(LogLevel::Debug, message)))
    end

    def error(context : String, message : String) : Nil
      @on_error.try(&.call(context, message))
      @on_log.try(&.call(LogEntry.new(LogLevel::Error, message, context)))
    end

    def warning(message : String) : Nil
      @on_warning.try(&.call(message))
      @on_log.try(&.call(LogEntry.new(LogLevel::Warn, message)))
    end

    def save(url : String, data : Bytes, content_type : String) : String?
      @on_save.try(&.call(url, data, content_type))
    end

    def load(url : String) : String?
      @on_load.try(&.call(url))
    end

    # Sentinel used by copy_with to distinguish "not provided" from "explicitly nil"
    private struct Unset
      INSTANCE = new

      def self.instance : self
        INSTANCE
      end
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def copy_with(
      timeout : Time::Span? = nil,
      html_fetch_timeout : Time::Span? = nil,
      connect_timeout : Time::Span? = nil,
      write_timeout : Time::Span? = nil,
      max_redirects : Int32? = nil,
      max_size : Int32? = nil,
      user_agent : String? = nil,
      accept_language : String? = nil,
      cache_size_limit : Int32? = nil,
      cache_entry_ttl : Time::Span? = nil,
      gray_placeholder_size : Int32? = nil,
      max_concurrent_requests : Int32? = nil,
      max_retries : Int32? = nil,
      retry_base_delay : Time::Span? = nil,
      retry_max_delay : Time::Span? = nil,
      on_save : Proc(String, Bytes, String, String?)? | Unset = Unset.instance,
      on_load : Proc(String, String?)? | Unset = Unset.instance,
      on_debug : Proc(String, Nil)? | Unset = Unset.instance,
      on_error : Proc(String, String, Nil)? | Unset = Unset.instance,
      on_warning : Proc(String, Nil)? | Unset = Unset.instance,
      on_log : Proc(LogEntry, Nil)? | Unset = Unset.instance,
    ) : Config
      Config.new(
        timeout: timeout || @timeout,
        html_fetch_timeout: html_fetch_timeout || @html_fetch_timeout,
        connect_timeout: connect_timeout || @connect_timeout,
        write_timeout: write_timeout || @write_timeout,
        max_redirects: max_redirects || @max_redirects,
        max_size: max_size || @max_size,
        user_agent: user_agent || @user_agent,
        accept_language: accept_language || @accept_language,
        cache_size_limit: cache_size_limit || @cache_size_limit,
        cache_entry_ttl: cache_entry_ttl || @cache_entry_ttl,
        gray_placeholder_size: gray_placeholder_size || @gray_placeholder_size,
        max_concurrent_requests: max_concurrent_requests || @max_concurrent_requests,
        max_retries: max_retries || @max_retries,
        retry_base_delay: retry_base_delay || @retry_base_delay,
        retry_max_delay: retry_max_delay || @retry_max_delay,
        on_save: on_save.is_a?(Unset) ? @on_save : on_save.as(Proc(String, Bytes, String, String?)?),
        on_load: on_load.is_a?(Unset) ? @on_load : on_load.as(Proc(String, String?)?),
        on_debug: on_debug.is_a?(Unset) ? @on_debug : on_debug.as(Proc(String, Nil)?),
        on_error: on_error.is_a?(Unset) ? @on_error : on_error.as(Proc(String, String, Nil)?),
        on_warning: on_warning.is_a?(Unset) ? @on_warning : on_warning.as(Proc(String, Nil)?),
        on_log: on_log.is_a?(Unset) ? @on_log : on_log.as(Proc(LogEntry, Nil)?),
      )
    end
  end
end
