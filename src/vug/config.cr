require "time"

module Vug
  class Config
    property timeout : Time::Span = 30.seconds
    property connect_timeout : Time::Span = 10.seconds
    property max_redirects : Int32 = 10
    property max_size : Int32 = 100 * 1024
    property user_agent : String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    property accept_language : String = "en-US,en;q=0.9"

    property cache_size_limit : Int32 = 10 * 1024 * 1024
    property cache_entry_ttl : Time::Span = 7.days

    property gray_placeholder_size : Int32 = 198

    property on_save : Proc(String, Bytes, String, String?)? = nil
    property on_load : Proc(String, String?)? = nil
    property on_debug : Proc(String, Nil)? = nil
    property on_error : Proc(String, Exception, Nil)? = nil
    property on_warning : Proc(String, Nil)? = nil

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
      on_save : Proc(String, Bytes, String, String?)? = nil,
      on_load : Proc(String, String?)? = nil,
      on_debug : Proc(String, Nil)? = nil,
      on_error : Proc(String, Exception, Nil)? = nil,
      on_warning : Proc(String, Nil)? = nil,
    )
      @timeout = timeout || @timeout
      @connect_timeout = connect_timeout || @connect_timeout
      @max_redirects = max_redirects || @max_redirects
      @max_size = max_size || @max_size
      @user_agent = user_agent || @user_agent
      @accept_language = accept_language || @accept_language
      @cache_size_limit = cache_size_limit || @cache_size_limit
      @cache_entry_ttl = cache_entry_ttl || @cache_entry_ttl
      @gray_placeholder_size = gray_placeholder_size || @gray_placeholder_size
      @on_save = on_save
      @on_load = on_load
      @on_debug = on_debug
      @on_error = on_error
      @on_warning = on_warning
    end

    def debug(message : String) : Nil
      @on_debug.try(&.call(message))
    end

    def error(context : String, ex : Exception) : Nil
      @on_error.try(&.call(context, ex))
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
  end
end
