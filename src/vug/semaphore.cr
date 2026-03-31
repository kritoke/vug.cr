module Vug
  class Semaphore
    def initialize(@limit : Int32)
      @channel = Channel(Nil).new(@limit)
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
