namespace :hosts do
  desc 'check github tokens'
  task check_github_tokens: :environment do
    host = Host.find_by_name('GitHub')
    host.host_instance.check_tokens
  end

  desc 'sync owners'
  task sync_owners: :environment do
    Owner.sync_least_recently_synced
  end

  desc 'Check status of all hosts'
  task check_status: :environment do
    Host.find_each do |host|
      host.check_status
    rescue => e
      # Silently continue on exceptions
    end
  end
  
  desc 'Check status of stale hosts only'
  task check_stale_status: :environment do
    Host.where('status_checked_at IS NULL OR status_checked_at < ?', 1.hour.ago).find_each do |host|
      host.check_status
    rescue => e
      # Silently continue on exceptions
    end
  end
end