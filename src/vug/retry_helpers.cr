module Vug
  # Shared retry and backoff utilities for transient failure handling.
  module RetryHelpers
    # Calculate exponential backoff delay with jitter.
    # Used for retrying transient failures (timeouts, socket errors, etc.)
    #
    # - attempt: current attempt number (0-indexed)
    # - base_delay: initial delay before first retry
    # - max_delay: maximum delay cap
    # Returns: delay duration with 0-25% random jitter added
    def self.backoff_delay(attempt : Int32, base_delay : Time::Span, max_delay : Time::Span) : Time::Span
      # Exponential backoff: base_delay * 2^attempt
      exponential = base_delay * (2 ** attempt)
      # Cap at max_delay
      capped = exponential > max_delay ? max_delay : exponential
      # Add jitter (0-25% of delay)
      jitter_ns = (rand * 0.25 * capped.total_nanoseconds).to_i64
      Time::Span.new(nanoseconds: capped.total_nanoseconds.to_i64 + jitter_ns)
    end

    # Execute a block with retry logic for transient failures.
    #
    # - max_retries: maximum number of retry attempts
    # - base_delay: initial delay between retries
    # - max_delay: maximum delay cap
    # - retryable: proc to determine if an exception is retryable
    # - on_retry: optional callback called before each retry (for logging)
    # - &block: the operation to execute
    #
    # Returns the block's result on success, or raises the last exception.
    def self.with_retry(
      max_retries : Int32,
      base_delay : Time::Span,
      max_delay : Time::Span,
      retryable : Proc(Exception, Bool)? = nil,
      on_retry : Proc(Int32, Exception, Time::Span, Nil)? = nil,
      & : -> T
    ) forall T
      attempt = 0
      last_error : Exception? = nil

      loop do
        begin
          return yield
        rescue ex : Exception
          last_error = ex

          # Check if exception is retryable
          is_retryable = retryable ? retryable.call(ex) : default_retryable?(ex)
          raise ex unless is_retryable

          if attempt < max_retries
            delay = backoff_delay(attempt, base_delay, max_delay)
            on_retry.try(&.call(attempt, ex, delay))
            sleep(delay)
            attempt += 1
          else
            raise ex
          end
        end
      end
    end

    # Default retryable check: IO timeouts, socket errors, IO errors, SSL errors.
    private def self.default_retryable?(ex : Exception) : Bool
      ex.is_a?(IO::TimeoutError) ||
        ex.is_a?(Socket::Error) ||
        ex.is_a?(IO::Error) ||
        ex.is_a?(OpenSSL::SSL::Error)
    end
  end
end
