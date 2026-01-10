require 'timeout'

module CronLock
  class TaskTimeout < StandardError; end

  # Acquire a lock and run the block. If lock is already held, exit silently.
  # Uses Redis SET NX EX for atomic lock acquisition with automatic expiry.
  #
  # Options:
  #   ttl: How long to hold the lock (also used as timeout if timeout not specified)
  #   timeout: How long before killing the task (defaults to ttl)
  #
  # Usage in rake task:
  #   CronLock.acquire("repositories:crawl", ttl: 30.minutes) do
  #     # task code here
  #   end
  #
  #   # With separate timeout (lock held longer than execution allowed)
  #   CronLock.acquire("long_task", ttl: 2.hours, timeout: 1.hour) do
  #     # task code here
  #   end
  #
  def self.acquire(name, ttl: 1.hour, timeout: nil)
    timeout ||= ttl
    lock_key = "cron_lock:#{name}"
    lock_value = "#{Socket.gethostname}:#{Process.pid}:#{Time.now.to_i}"

    # SET NX EX - set if not exists with expiry
    acquired = REDIS.set(lock_key, lock_value, nx: true, ex: ttl.to_i)

    unless acquired
      puts "[CronLock] Skipping #{name} - already running"
      return false
    end

    begin
      puts "[CronLock] Acquired lock for #{name} (timeout: #{timeout.to_i}s)"
      Timeout.timeout(timeout.to_i, TaskTimeout) do
        yield
      end
    rescue TaskTimeout
      puts "[CronLock] TIMEOUT: #{name} exceeded #{timeout.to_i}s - killed"
    ensure
      # Only release if we still hold the lock (check value matches)
      current = REDIS.get(lock_key)
      if current == lock_value
        REDIS.del(lock_key)
        puts "[CronLock] Released lock for #{name}"
      else
        puts "[CronLock] Lock expired or taken by another process"
      end
    end

    true
  end
end
