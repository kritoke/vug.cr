module Vug
  # Semaphore implementation using a buffered channel. Each `acquire` consumes
  # a token from the channel, and each `release` returns a token. The channel
  # is pre-filled with @limit tokens so concurrent callers can immediately
  # acquire up to @limit permits.
  #
  # `acquire` accepts an optional timeout (default 30 seconds). When the timeout
  # expires, `acquire` returns `false` instead of blocking indefinitely. This
  # prevents permit loss from fiber cancellation: if a fiber is cancelled after
  # consuming a token but before `release`, the timeout ensures other callers
  # don't deadlock waiting for a permit that will never be returned.
  class Semaphore
    DEFAULT_ACQUIRE_TIMEOUT = 30.seconds

    def initialize(@limit : Int32)
      @channel = Channel(Nil).new(@limit)
      # Pre-fill channel with tokens - each acquire/receive consumes one token
      @limit.times { @channel.send(nil) }
    end

    # Attempt to acquire a permit. Returns `true` on success, `false` if the
    # timeout expires before a permit is available.
    def acquire(timeout : Time::Span = DEFAULT_ACQUIRE_TIMEOUT) : Bool
      select
      when @channel.receive
        true
      when timeout(timeout)
        false
      end
    end

    def release : Nil
      @channel.send(nil)
    end
  end
end
