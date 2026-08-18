class SyncCommitStatsWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(repository_id)
    Repository.find_by_id(repository_id).try(:sync_commit_stats)
  end
end