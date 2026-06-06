require "uri"
require "time"

module Vug
  # Mutable state threaded through the fetch loop, replacing scattered
  # local variables and positional tuple returns.
  #
  # Owns the per-request state for a single `Fetcher#fetch` call: the URL
  # being chased, the redirect/gray-placeholder counters, the visited-set
  # used to detect redirect loops, the initial DNS resolutions used to
  # detect DNS rebinding, and the start time used to enforce the timeout.
  class LoopState
    property current_url : String
    property current_uri : URI?
    property redirects : Int32 = 0
    property gray_placeholder_attempts : Int32 = 0
    getter visited_urls : Set(String)
    getter initial_dns_ips : Hash(String, Array(String))
    getter start_time : Time::Span
    getter initial_url : String

    MAX_GRAY_ATTEMPTS = 3

    def initialize(@initial_url : String, @start_time : Time::Span)
      @current_url = @initial_url
      @current_uri = URI.parse(@initial_url) rescue nil
      @visited_urls = Set(String).new
      @initial_dns_ips = {} of String => Array(String)
    end
  end
end
