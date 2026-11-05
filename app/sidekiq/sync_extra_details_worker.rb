class SyncExtraDetailsWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options queue: 'extra', lock: :until_and_while_executing, lock_expiration: 1.day.to_i, on_conflict: {server: :reschedule}

  def perform(repository_id)
    Repository.find_by_id(repository_id).try(:sync_extra_details)
  end
end
