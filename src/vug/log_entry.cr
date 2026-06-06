require "json"
require "time"

module Vug
  # Log severity levels for structured logging.
  enum LogLevel
    Debug
    Info
    Warn
    Error
  end

  # A structured log entry with level, message, optional context, and timestamp.
  class LogEntry
    include JSON::Serializable

    getter level : LogLevel
    getter message : String
    getter context : String?
    getter timestamp : Time

    def initialize(@level : LogLevel, @message : String, @context : String? = nil, @timestamp : Time = Time.utc)
    end
  end
end
