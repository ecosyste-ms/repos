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
    processed = 0
    with_topics = 0

    Host.order(:repositories_count).each do |host|
      cursor_key = "topics_backfill:#{host.id}"
      done_key = "topics_backfill_done:#{host.id}"
      has_cursor = REDIS.exists?(cursor_key)
      already_done = REDIS.exists?(done_key)

      # Skip if already completed or has topics (unless we have a cursor to resume)
      next if !has_cursor && (already_done || host.topics.exists?)

      if host.repositories_count > large_host_threshold || has_cursor
        backfill_large_host(host, batch_size)
      else
        count = backfill_small_host(host)
        processed += 1
        with_topics += 1 if count > 0
      end
    end

    puts "Processed #{processed} small hosts, #{with_topics} had topics" if processed > 0
  end

  def backfill_small_host(host)
    count = Topic.sync_for_host(host)
    REDIS.set("topics_backfill_done:#{host.id}", "1", ex: 7.days.to_i)
    puts "#{host.name}: #{count} topics" if count > 0
    count
  end

  def backfill_large_host(host, batch_size)
    host_id = host.id
    cursor_key = "topics_backfill:#{host_id}"
    last_id = REDIS.get(cursor_key).to_i

    # Get max_id with fast indexed lookup (ORDER BY id DESC LIMIT 1)
    max_id = Repository.where(host_id: host_id).order(id: :desc).limit(1).pick(:id)
    unless max_id
      puts "Skipping #{host.name} - no repositories"
      REDIS.set("topics_backfill_done:#{host_id}", "1", ex: 7.days.to_i)
      return
    end

    if last_id > 0
      puts "Backfilling #{host.name} - resuming from id #{last_id} (max: #{max_id})..."
    else
      puts "Backfilling #{host.name} (#{host.repositories_count} repos, max_id: #{max_id})..."
    end

    batch_num = 0
    total_upserts = 0
    id_step = 50_000  # Fixed ID range per batch - avoids ORDER BY

    current_start = last_id
    while current_start < max_id
      batch_num += 1
      current_end = current_start + id_step
      topic_counts = Hash.new(0)

      # Query by ID range - no ORDER BY needed, uses index on (host_id) + id range
      repos = Repository.where(host_id: host_id)
                        .where('id > ? AND id <= ?', current_start, current_end)
                        .select(:id, :topics)
                        .to_a

      repos.each do |repo|
        next if repo.topics.blank?
        repo.topics.each { |t| topic_counts[t] += 1 }
      end

      upserts = flush_topic_counts(host_id, topic_counts)
      total_upserts += upserts
      REDIS.set(cursor_key, current_end)
      puts "  Batch #{batch_num}: #{upserts} upserts (#{repos.size} repos, id #{current_start}-#{current_end})"

      current_start = current_end
    end

    # Clear cursor and mark as done
    REDIS.del(cursor_key)
    REDIS.set("topics_backfill_done:#{host_id}", "1", ex: 7.days.to_i)
    puts "  Done! #{total_upserts} total upserts across #{batch_num} batches"
  end

  def flush_topic_counts(host_id, topic_counts)
    return 0 if topic_counts.empty?

    values = topic_counts.map do |name, count|
      escaped_name = ActiveRecord::Base.connection.quote(name)
      "(#{host_id}, #{escaped_name}, #{count}, NOW(), NOW())"
    end.join(",\n")

    sql = <<~SQL
      INSERT INTO topics (host_id, name, repositories_count, created_at, updated_at)
      VALUES #{values}
      ON CONFLICT (host_id, name) DO UPDATE SET
        repositories_count = topics.repositories_count + EXCLUDED.repositories_count,
        updated_at = NOW()
    SQL

    result = ActiveRecord::Base.connection.execute(sql)
    result.cmd_tuples rescue 0
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
