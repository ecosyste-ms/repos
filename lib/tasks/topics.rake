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

  desc 'Backfill topics for a single host (use for initial population)'
  task :backfill_host, [:host_name] => :environment do |t, args|
    host = Host.find_by_name!(args[:host_name])
    puts "Backfilling topics for #{host.name}..."
    puts "Disabling statement timeout..."

    ActiveRecord::Base.connection.execute("SET statement_timeout = 0")

    start_time = Time.current
    count = Topic.sync_for_host(host)
    elapsed = Time.current - start_time

    puts "Done! #{count} topics synced in #{elapsed.round(1)}s"
  end

  desc 'Backfill topics for all hosts (run once for initial population)'
  task backfill_all: :environment do
    puts "Disabling statement timeout..."
    ActiveRecord::Base.connection.execute("SET statement_timeout = 0")

    Host.order(:name).each do |host|
      if host.topics.exists?
        puts "Skipping #{host.name} - already has topics"
        next
      end

      puts "Backfilling topics for #{host.name}..."

      start_time = Time.current
      count = Topic.sync_for_host(host)
      elapsed = Time.current - start_time

      puts "  #{count} topics synced in #{elapsed.round(1)}s"
    end
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
