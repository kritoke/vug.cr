module Vug
  # Semaphore implementation using a buffered channel. Each `acquire` consumes
  # a token from the channel, and each `release` returns a token. The channel
  # is pre-filled with @limit tokens so concurrent callers can immediately
  # acquire up to @limit permits.
  class Semaphore
    def initialize(@limit : Int32)
      @channel = Channel(Nil).new(@limit)
      # Pre-fill channel with tokens - each acquire/receive consumes one token
      @limit.times { @channel.send(nil) }
    end

    def acquire : Nil
      @channel.receive
    end

    def release : Nil
      @channel.send(nil)
    end
  end
end
