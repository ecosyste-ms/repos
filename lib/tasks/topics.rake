require_relative '../cron_lock'

namespace :topics do
  desc 'Sync topics table from repository topics arrays (nightly job)'
  task sync: :environment do
    # TODO(BACKFILL): Disabled until initial backfill is complete
    # Remove this check once backfill has run
    if ENV['ENABLE_TOPICS_SYNC'] != 'true'
      puts "[topics:sync] Disabled - set ENABLE_TOPICS_SYNC=true after backfill complete"
      return
    end

    CronLock.acquire("topics:sync", ttl: 6.hours) do
      Topic.sync_all
    end
  end

  desc 'Backfill topics for all hosts'
  task :backfill, [:batch_size] => :environment do |t, args|
    batch_size = (args[:batch_size] || 10_000).to_i
    large_host_threshold = 100_000

    Host.order(:repositories_count).each do |host|
      if host.topics.exists?
        puts "Skipping #{host.name} - already has topics"
        next
      end

      if host.repositories_count > large_host_threshold
        backfill_large_host(host, batch_size)
      else
        backfill_small_host(host)
      end
    end
  end

  def backfill_small_host(host)
    puts "Backfilling #{host.name} (#{host.repositories_count} repos)..."
    start_time = Time.current
    count = Topic.sync_for_host(host)
    elapsed = Time.current - start_time
    puts "  #{count} topics in #{elapsed.round(1)}s"
  end

  def backfill_large_host(host, batch_size)
    host_id = host.id
    min_id, max_id = Repository.where(host_id: host_id).pick(Arel.sql('MIN(id), MAX(id)'))

    unless min_id && max_id
      puts "Skipping #{host.name} - no repositories"
      return
    end

    puts "Backfilling #{host.name} (#{host.repositories_count} repos) in batches of #{batch_size}..."
    puts "  Repository ID range: #{min_id} - #{max_id}"

    current = min_id
    batch_num = 0
    total_upserts = 0

    while current <= max_id
      batch_num += 1
      batch_end = current + batch_size - 1

      start_time = Time.current

      sql = <<~SQL
        INSERT INTO topics (host_id, name, repositories_count, created_at, updated_at)
        SELECT
          #{host_id},
          topic_name,
          cnt,
          NOW(),
          NOW()
        FROM (
          SELECT unnest(topics) AS topic_name, COUNT(*) AS cnt
          FROM repositories
          WHERE host_id = #{host_id}
            AND id BETWEEN #{current} AND #{batch_end}
            AND topics IS NOT NULL
            AND array_length(topics, 1) > 0
          GROUP BY topic_name
        ) t
        ON CONFLICT (host_id, name) DO UPDATE SET
          repositories_count = topics.repositories_count + EXCLUDED.repositories_count,
          updated_at = NOW()
      SQL

      result = ActiveRecord::Base.connection.execute(sql)
      elapsed = Time.current - start_time
      upserts = result.cmd_tuples rescue 0
      total_upserts += upserts

      puts "  Batch #{batch_num}: #{upserts} upserts in #{elapsed.round(1)}s"

      current = batch_end + 1
    end

    puts "  Done! #{total_upserts} total upserts across #{batch_num} batches"
  end

  desc 'Show topic stats'
  task stats: :environment do
    total = Topic.count
    puts "Total topics: #{total}"
    puts ""

    Host.joins(:topics)
        .select('hosts.name, COUNT(topics.id) as topic_count')
        .group('hosts.id')
        .order('topic_count DESC')
        .limit(20)
        .each do |host|
      puts "  #{host.name}: #{host.topic_count}"
    end
  end
end
