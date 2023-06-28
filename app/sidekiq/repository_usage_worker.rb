class RepositoryUsageWorker
  include Sidekiq::Worker

  def perform(repository_id)
    repository = Repository.find(repository_id)
    RepositoryUsage.from_repository(repository) if repository
  end
end