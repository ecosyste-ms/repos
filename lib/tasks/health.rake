require_relative '../cron_lock'

namespace :health do
  desc "Check database and system health - run this to diagnose performance issues"
  task check: :environment do
    puts "=" * 60
    puts "HEALTH CHECK - #{Time.current}"
    puts "=" * 60

    # Database connection stats
    puts "\n## Database Connections"
    result = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT state, count(*)
      FROM pg_stat_activity
      WHERE datname = current_database()
      GROUP BY state
    SQL
    result.each { |row| puts "  #{row['state'] || 'null'}: #{row['count']}" }

    # Long running queries
    puts "\n## Queries Running > 1 minute"
    result = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT count(*) as cnt
      FROM pg_stat_activity
      WHERE state = 'active'
        AND query_start < now() - interval '1 minute'
        AND datname = current_database()
    SQL
    count = result.first['cnt']
    puts "  Count: #{count}"

    if count > 0
      puts "\n  Query patterns:"
      result = ActiveRecord::Base.connection.execute(<<~SQL)
        SELECT left(query, 80) as pattern, count(*) as cnt
        FROM pg_stat_activity
        WHERE state = 'active'
          AND query_start < now() - interval '1 minute'
          AND datname = current_database()
        GROUP BY left(query, 80)
        ORDER BY count(*) DESC
        LIMIT 5
      SQL
      result.each { |row| puts "    #{row['cnt']}x: #{row['pattern'].gsub("\n", ' ')}" }
    end

    # Very old queries (potential zombies)
    puts "\n## Queries Running > 10 minutes (potential problems)"
    result = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT pid,
             extract(epoch from (now() - query_start))::int as seconds,
             left(query, 60) as query
      FROM pg_stat_activity
      WHERE state = 'active'
        AND query_start < now() - interval '10 minutes'
        AND datname = current_database()
      ORDER BY query_start
      LIMIT 10
    SQL
    if result.count > 0
      result.each do |row|
        mins = row['seconds'] / 60
        puts "  PID #{row['pid']} (#{mins}min): #{row['query'].gsub("\n", ' ')}"
      end
    else
      puts "  None - good!"
    end

    # Sidekiq stats
    puts "\n## Sidekiq Queues"
    Sidekiq::Queue.all.each do |queue|
      puts "  #{queue.name}: #{queue.size} jobs"
    end
    puts "  Retries: #{Sidekiq::RetrySet.new.size}"
    puts "  Scheduled: #{Sidekiq::ScheduledSet.new.size}"
    puts "  Dead: #{Sidekiq::DeadSet.new.size}"

    # Sidekiq processes
    puts "\n## Sidekiq Processes"
    ps = Sidekiq::ProcessSet.new
    puts "  Active processes: #{ps.size}"
    ps.each do |process|
      puts "    #{process['hostname']}: #{process['busy']}/#{process['concurrency']} busy"
    end

    # Table sizes (estimates)
    puts "\n## Large Tables (estimated rows)"
    %w[dependencies repository_usages repositories manifests tags].each do |table|
      result = ActiveRecord::Base.connection.execute(<<~SQL)
        SELECT n_live_tup as estimate
        FROM pg_stat_user_tables
        WHERE relname = '#{table}'
      SQL
      count = result.first&.fetch('estimate', 0) || 0
      puts "  #{table}: #{number_with_delimiter(count)}"
    end

    # Cron locks
    puts "\n## Active Cron Locks"
    keys = REDIS.keys("cron_lock:*")
    if keys.empty?
      puts "  None"
    else
      keys.sort.each do |key|
        value = REDIS.get(key)
        ttl = REDIS.ttl(key)
        name = key.sub("cron_lock:", "")
        if value
          host, pid, started = value.split(":")
          started_at = Time.at(started.to_i) rescue nil
          running_for = started_at ? ((Time.now - started_at) / 60).round : "?"
          puts "  #{name}: #{running_for}min (TTL: #{ttl}s)"
        end
      end
    end

    # Check for disabled features
    puts "\n## Disabled Features (TODO(DB_PERF))"
    disabled = []
    disabled << "RepositoryUsage.from_repository" if RepositoryUsage.from_repository(nil).nil? rescue true
    disabled << "RepositoryUsage.crawl" if RepositoryUsage.crawl.nil? rescue true
    disabled << "Host#topics returns []" if Host.new.topics == []
    disabled << "Repository.topics returns []" if Repository.topics == []

    if disabled.any?
      disabled.each { |d| puts "  - #{d}" }
    else
      puts "  None disabled"
    end

    puts "\n" + "=" * 60
    puts "END HEALTH CHECK"
    puts "=" * 60
  end

  desc "Kill queries running longer than specified minutes (default: 10)"
  task :kill_slow_queries, [:minutes] => :environment do |t, args|
    minutes = (args[:minutes] || 10).to_i
    puts "Killing queries running longer than #{minutes} minutes..."

    result = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT pg_terminate_backend(pid), pid, left(query, 60) as query
      FROM pg_stat_activity
      WHERE state = 'active'
        AND query_start < now() - interval '#{minutes} minutes'
        AND datname = current_database()
        AND pid != pg_backend_pid()
    SQL

    if result.count > 0
      result.each { |row| puts "  Killed PID #{row['pid']}: #{row['query']}" }
      puts "Killed #{result.count} queries"
    else
      puts "No slow queries to kill"
    end
  end

  desc "Show current cron locks"
  task locks: :environment do
    puts "Current Cron Locks"
    puts "=" * 60

    keys = REDIS.keys("cron_lock:*")

    if keys.empty?
      puts "No active locks"
    else
      keys.sort.each do |key|
        value = REDIS.get(key)
        ttl = REDIS.ttl(key)
        name = key.sub("cron_lock:", "")

        if value
          host, pid, started = value.split(":")
          started_at = Time.at(started.to_i) rescue nil
          running_for = started_at ? ((Time.now - started_at) / 60).round : "?"

          puts "#{name}"
          puts "  Host: #{host}, PID: #{pid}"
          puts "  Running: #{running_for} min, TTL: #{ttl}s"
          puts ""
        end
      end
    end
  end

  desc "Clear a specific cron lock (use with caution)"
  task :clear_lock, [:name] => :environment do |t, args|
    unless args[:name]
      puts "Usage: rake health:clear_lock[task_name]"
      puts "Example: rake health:clear_lock[repositories:crawl]"
      exit 1
    end

    key = "cron_lock:#{args[:name]}"
    if REDIS.exists?(key)
      REDIS.del(key)
      puts "Cleared lock: #{args[:name]}"
    else
      puts "No lock found for: #{args[:name]}"
    end
  end

  desc "Clear all cron locks (use with caution)"
  task clear_all_locks: :environment do
    keys = REDIS.keys("cron_lock:*")

    if keys.empty?
      puts "No locks to clear"
    else
      keys.each { |key| REDIS.del(key) }
      puts "Cleared #{keys.count} locks"
    end
  end

  def number_with_delimiter(number)
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end
end
