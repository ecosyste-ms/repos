class SyncOwnerWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(host_id, login, force = false)
    Host.find_by_id(host_id).try(:sync_owner, login, force: force)
  end
end