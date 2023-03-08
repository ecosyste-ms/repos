class SyncCommitStatsWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed

  def perform(repository_id)
    Repository.find_by_id(repository_id).try(:sync_commit_stats)
  end
end