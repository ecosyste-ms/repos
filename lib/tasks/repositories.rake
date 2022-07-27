namespace :repositories do
  desc 'sync least recently synced repos'
  task sync_least_recent: :environment do 
    Host.all.each do |host|
      host.repositories.order('last_synced_at ASC').where(fork: false).limit(10_000).select('id').each(&:sync_async)
    end
  end

  desc 'sync repos that have been recently active'
  task sync_recently_active: :environment do 
    Host.all.each do |host|
      host.sync_recently_changed_repos_async
    end
  end

  desc 'parse missing dependencies'
  task parse_missing_dependencies: :environment do 
    Repository.parse_dependencies_async
  end

  desc 'crawl repositories'
  task crawl: :environment do
    Host.all.each do |host|
      host.crawl_repositories
    end
  end
end