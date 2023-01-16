namespace :hosts do
  desc 'update repository counts'
  task update_repository_counts: :environment do
    Host.all.each(&:update_repository_counts)
  end

  desc 'check github tokens'
  task check_github_tokens: :environment do
    host = Host.find_by_name('GitHub')
    host.host_instance.check_tokens
  end
end