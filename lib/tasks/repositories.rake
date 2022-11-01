namespace :repositories do
  desc 'sync least recently synced repos'
  task sync_least_recent: :environment do 
    if Sidekiq::Queue.new('default').size < 10_000
      Repository.order('last_synced_at ASC').limit(5_000).select('id').each(&:sync_async)
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

  desc 'download tags'
  task download_tags: :environment do 
    host = Host.find_by_name('GitHub')
    host.host_instance.sync_repos_with_tags
  end

  desc 'sync tags'
  task sync_tags: :environment do
    Repository.download_tags_async
  end

  desc 'crawl repositories'
  task crawl: :environment do
    Host.all.each do |host|
      host.crawl_repositories_async
    end
  end

  desc 'update package usages'
  task update_package_usages: :environment do
    # Repository.update_package_usages_async
  end

  desc 'update metadata files'
  task update_metadata_files: :environment do
    Repository.update_metadata_files_async
  end
end