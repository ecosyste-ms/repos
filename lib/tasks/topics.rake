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
    with_direct_connection do
      host = Host.find_by_name!(args[:host_name])
      puts "Backfilling topics for #{host.name}..."

      start_time = Time.current
      count = Topic.sync_for_host(host)
      elapsed = Time.current - start_time

      puts "Done! #{count} topics synced in #{elapsed.round(1)}s"
    end
  end

  desc 'Backfill topics for all hosts (run once for initial population)'
  task backfill_all: :environment do
    with_direct_connection do
      Host.order(:repositories_count).each do |host|
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
  end

  def with_direct_connection
    migration_url = ENV['MIGRATION_DATABASE_URL']
    if migration_url
      puts "Attempting direct database connection (bypassing PgBouncer)..."
      begin
        ActiveRecord::Base.establish_connection(migration_url)
        ActiveRecord::Base.connection.execute("SET statement_timeout = 0")
        puts "Connected directly to PostgreSQL"
      rescue ActiveRecord::DatabaseConnectionError => e
        puts "Direct connection failed - port 5432 not accessible"
        puts "Falling back to PgBouncer connection (300s timeout per query)"
        puts ""
        puts "For large hosts, run this task from the database server:"
        puts "  cd /path/to/app && RAILS_ENV=production bundle exec rake topics:backfill_all"
        puts ""
        ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'] || Rails.application.config.database_configuration[Rails.env])
      end
    else
      puts "Using default connection (300s statement timeout)"
    end

    yield
  ensure
    ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'] || Rails.application.config.database_configuration[Rails.env])
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
