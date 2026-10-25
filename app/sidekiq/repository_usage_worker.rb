class RepositoryUsageWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options queue: 'usage', lock: :until_executing, lock_expiration: 1.day.to_i

  def perform(repository_id)
    return unless RepositoryUsage.writes_enabled?(repository_id)

    repository = Repository.select(:id).find_by(id: repository_id)
    RepositoryUsage.from_repository(repository) if repository
  end
end
