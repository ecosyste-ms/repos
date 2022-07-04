namespace :hosts do
  desc 'update repository counts'
  task update_repository_counts: :environment do
    Host.all.each(&:update_repository_counts)
  end
end