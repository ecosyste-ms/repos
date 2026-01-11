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
      cursor_key = "topics_backfill:#{host.id}"
      has_cursor = REDIS.exists?(cursor_key)

      # If we have a cursor, resume regardless of existing topics
      # Otherwise skip hosts that already have topics
      if !has_cursor && host.topics.exists?
        puts "Skipping #{host.name} - already has topics"
        next
      end

      if host.repositories_count > large_host_threshold || has_cursor
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
    cursor_key = "topics_backfill:#{host_id}"
    last_id = REDIS.get(cursor_key).to_i

    if last_id > 0
      puts "Backfilling #{host.name} - resuming from id #{last_id}..."
    else
      puts "Backfilling #{host.name} (#{host.repositories_count} repos) in batches of #{batch_size}..."
    end

    batch_num = 0
    total_upserts = 0
    topic_counts = Hash.new(0)
    repos_in_batch = 0
    current_id = 0

    Repository.where(host_id: host_id)
              .where('id > ?', last_id)
              .where.not(topics: nil)
              .order(:id)
              .select(:id, :topics)
              .each_hash do |row|
      next unless row['topics'].present?

      current_id = row['id'].to_i

      # Parse the PostgreSQL array format {topic1,topic2,"topic with spaces"}
      topics = parse_pg_array(row['topics'])
      topics.each { |t| topic_counts[t] += 1 }
      repos_in_batch += 1

      # Flush batch when we hit batch_size repos
      if repos_in_batch >= batch_size
        batch_num += 1
        upserts = flush_topic_counts(host_id, topic_counts)
        total_upserts += upserts
        REDIS.set(cursor_key, current_id)
        puts "  Batch #{batch_num}: #{upserts} upserts (#{repos_in_batch} repos, cursor: #{current_id})"
        topic_counts.clear
        repos_in_batch = 0
      end
    end

    # Flush remaining
    if topic_counts.any?
      batch_num += 1
      upserts = flush_topic_counts(host_id, topic_counts)
      total_upserts += upserts
      puts "  Batch #{batch_num}: #{upserts} upserts (#{repos_in_batch} repos)"
    end

    # Clear cursor on completion
    REDIS.del(cursor_key)
    puts "  Done! #{total_upserts} total upserts across #{batch_num} batches"
  end

  def parse_pg_array(str)
    return [] if str.nil? || str == '{}'
    # Remove outer braces and parse CSV-like format
    inner = str[1..-2]
    return [] if inner.nil? || inner.empty?

    result = []
    current = ''
    in_quotes = false

    inner.each_char do |c|
      if c == '"' && !in_quotes
        in_quotes = true
      elsif c == '"' && in_quotes
        in_quotes = false
      elsif c == ',' && !in_quotes
        result << current unless current.empty?
        current = ''
      else
        current << c
      end
    end
    result << current unless current.empty?
    result
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
