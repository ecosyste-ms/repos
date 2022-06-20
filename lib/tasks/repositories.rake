namespace :repositories do
  desc 'sync least recently synced repos'
  task sync_least_recent: :environment do 
    Host.all.each do |host|
      host.repositories.order('last_synced_at DESC').limit(1000).each(&:sync_async)
    end
  end

  desc 'sync repos that have been recently active'
  task sync_recently_active: :environment do 
    Host.all.each do |host|
      host.sync_recently_changed_repos_async
    end
  end
end