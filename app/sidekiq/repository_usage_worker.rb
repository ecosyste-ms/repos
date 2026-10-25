class RepositoryUsageWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options queue: 'usage', lock: :until_executing, lock_ttl: 1.day.to_i

  def perform(repository_id)
    return unless RepositoryUsage.writes_enabled?(repository_id)
    return if REDIS.zscore("#{RepositoryUsageBackfillWorker.key}:pending", repository_id)

    repository = Repository.select(:id).find_by(id: repository_id)
    RepositoryUsage.from_repository(repository) if repository
  rescue RepositoryUsage::ReadLimitExceeded, RepositoryUsage::InvalidContribution => error
    RepositoryUsageBackfillWorker.record_failure(repository_id, error)
  end
end
