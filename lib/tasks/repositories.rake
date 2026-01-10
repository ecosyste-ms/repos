require_relative '../cron_lock'

namespace :repositories do
  desc 'sync least recently synced repos'
  task sync_least_recent: :environment do
    CronLock.acquire("repositories:sync_least_recent", ttl: 20.minutes) do
      if Sidekiq::Queue.new('default').size < 10_000
        Repository.order('last_synced_at ASC').limit(2_000).select('id').each(&:sync_async)
      end
    end
  end

  desc 'sync repos that have been recently active'
  task sync_recently_active: :environment do
    CronLock.acquire("repositories:sync_recently_active", ttl: 30.minutes) do
      Host.all.each do |host|
        host.sync_recently_changed_repos_async
      end
    end
  end

  desc 'sync extra details on repos that files have changed'
  task sync_extra_details: :environment do
    CronLock.acquire("repositories:sync_extra_details", ttl: 10.minutes) do
      # Repository.sync_extra_details_async
    end
  end

  desc 'parse missing dependencies'
  task parse_missing_dependencies: :environment do
    CronLock.acquire("repositories:parse_missing_dependencies", ttl: 30.minutes) do
      Repository.parse_dependencies_async
    end
  end

  desc 'download tags'
  task download_tags: :environment do
    CronLock.acquire("repositories:download_tags", ttl: 40.minutes) do
      host = Host.find_by_name('GitHub')
      host.host_instance.sync_repos_with_tags
    end
  end

  desc 'sync tags'
  task sync_tags: :environment do
    CronLock.acquire("repositories:sync_tags", ttl: 1.hour) do
      Repository.download_tags_async
    end
  end

  desc 'crawl repositories'
  task crawl: :environment do
    CronLock.acquire("repositories:crawl", ttl: 10.minutes) do
      Host.all.each do |host|
        host.crawl_repositories_async
      end
    end
  end

  desc 'update metadata files'
  task update_metadata_files: :environment do
    CronLock.acquire("repositories:update_metadata_files", ttl: 1.hour) do
      Repository.update_metadata_files_async
    end
  end

  desc 'fetch dependencies for github actions tags'
  task fetch_dependencies_for_github_actions_tags: :environment do
    CronLock.acquire("repositories:fetch_dependencies_for_github_actions_tags", ttl: 23.hours) do
      Repository.parse_dependencies_for_github_actions_tags
    end
  end

  desc 'clean up sidekiq unique jobs'
  task clean_up_sidekiq_unique_jobs: :environment do
    CronLock.acquire("repositories:clean_up_sidekiq_unique_jobs", ttl: 6.days) do
      REDIS.del('uniquejobs:digests')
    end
  end
end