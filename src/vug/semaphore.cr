require "mutex"

module Vug
  class Semaphore
    DEFAULT_ACQUIRE_TIMEOUT = 30.seconds

    def initialize(@limit : Int32)
      @channel = Channel(Nil).new(@limit)
      @limit.times { @channel.send(nil) }
    end

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

  class SharedState
    def self.instance : self
      @@instance_mutex.synchronize do
        @@instance ||= new
      end
    end

    def self.instance=(value : self)
      @@instance = value
    end

    def initialize
      @semaphore_mutex = Mutex.new
    end

    # NOTE: The semaphore is process-wide and only the first-initialized limit
    # is used. Subsequent calls to semaphore() with different limits are ignored.
    # This is intentional to avoid the overhead of Atomic or additional Mutex.
    def semaphore(limit : Int32) : Semaphore
      @semaphore_mutex.synchronize do
        @semaphore ||= Semaphore.new(limit)
      end
    end

    private getter semaphore_mutex : Mutex
    private property semaphore : Semaphore? = nil

    @@instance_mutex = Mutex.new
  end

  def self.shared_semaphore(limit : Int32) : Semaphore
    SharedState.instance.semaphore(limit)
  end
end
