namespace :hosts do
  desc 'update repository counts'
  task update_repository_counts: :environment do
    Host.all.each(&:update_repositories_count)
  end

  desc 'check github tokens'
  task check_github_tokens: :environment do
    host = Host.find_by_name('GitHub')
    host.host_instance.check_tokens
  end

  desc 'sync owners'
  task sync_owners: :environment do
    Owner.sync_least_recently_synced
  end
end