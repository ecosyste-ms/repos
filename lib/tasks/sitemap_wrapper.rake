require_relative '../cron_lock'

namespace :sitemap do
  desc 'Refresh sitemap with lock (wraps sitemap_generator)'
  task refresh_with_lock: :environment do
    CronLock.acquire("sitemap:refresh", ttl: 23.hours) do
      Rake::Task['sitemap:refresh'].invoke
    end
  end
end
