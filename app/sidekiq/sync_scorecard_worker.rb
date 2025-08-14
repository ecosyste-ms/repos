class SyncScorecardWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(repo_id)
    Repository.find_by_id(repo_id)&.sync_scorecard
  end
end