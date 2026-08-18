class SyncInactiveRepositoryWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(repository_id)
    repository = Repository.find_by_id(repository_id)
    repository.sync if repository&.inactive_sync_due?
  end
end
