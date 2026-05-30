require "../spec_helper"
require "../../src/vug/semaphore"

describe Vug::Semaphore do
  describe "construction" do
    it "creates a semaphore with the given limit" do
      sem = Vug::Semaphore.new(5)
      sem.should be_a(Vug::Semaphore)
    end

    it "creates a semaphore with limit 1" do
      sem = Vug::Semaphore.new(1)
      sem.should be_a(Vug::Semaphore)
    end
  end

  describe "#acquire and #release" do
    it "acquire and release cycle works" do
      sem = Vug::Semaphore.new(1)
      sem.acquire
      sem.release
      true.should be_true
    end

    it "can acquire up to the limit" do
      sem = Vug::Semaphore.new(3)
      3.times { sem.acquire }
      3.times { sem.release }
      true.should be_true
    end

    it "release after acquire allows another acquire" do
      sem = Vug::Semaphore.new(1)
      sem.acquire
      sem.release
      sem.acquire
      sem.release
      true.should be_true
    end
  end

  describe "concurrency behavior" do
    it "blocks when semaphore is fully acquired" do
      sem = Vug::Semaphore.new(1)
      sem.acquire

      result_channel = Channel(Symbol).new

      spawn do
        sem.acquire
        result_channel.send(:acquired)
        sem.release
      end

      # Give the fiber a chance to run — it should block on acquire
      select
      when msg = result_channel.receive
        # Should NOT get here — the spawn should be blocked
        msg.should eq(:should_not_reach)
      when timeout(50.milliseconds)
        # Expected: spawn is blocked because the only permit is held
      end

      sem.release

      # Now the spawn should be able to acquire
      msg = result_channel.receive
      msg.should eq(:acquired)
    end

    it "allows multiple concurrent acquires up to limit" do
      sem = Vug::Semaphore.new(3)
      results = Channel(Nil).new(3)

      3.times do
        spawn do
          sem.acquire
          results.send(nil)
        end
      end

      received = 0
      3.times do
        select
        when results.receive
          received += 1
        when timeout(1.second)
          break
        end
      end

      received.should eq(3)

      3.times { sem.release }
    end

    it "released permits allow waiting fibers to proceed" do
      sem = Vug::Semaphore.new(2)
      sem.acquire
      sem.acquire

      done = Channel(Nil).new

      spawn do
        sem.acquire
        done.send(nil)
        sem.release
      end

      # The spawn should be blocked — no permit available
      select
      when done.receive
        # Should not reach here yet
        true.should be_false
      when timeout(50.milliseconds)
        # Expected: spawn is blocked
      end

      sem.release

      select
      when done.receive
        # Now the spawn should have completed
        true.should be_true
      when timeout(1.second)
        true.should be_false
      end
    end
  end
end
