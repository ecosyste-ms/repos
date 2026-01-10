require_relative '../cron_lock'

namespace :packages do
  desc 'sync registries'
  task sync_registries: :environment do
    CronLock.acquire("packages:sync_registries", ttl: 23.hours) do
      Registry.sync_all
    end
  end

  desc 'sync packages'
  task sync_packages: :environment do
    CronLock.acquire("packages:sync_packages", ttl: 23.hours) do
      PackageUsage.sync_packages
    end
  end
end