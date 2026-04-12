module Vug
  module Diagnostics
    # Format an exception into a single-line context-aware string with backtrace
    def self.format_exception(ex : Exception, prefix : String? = nil) : String
      message = prefix || ex.message || "Unknown error"
      stack = ex.backtrace.join("\n")
      "#{message} | exception=#{ex.class} | backtrace=\n#{stack}"
    end
  end
end
