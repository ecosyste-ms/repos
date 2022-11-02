class SyncOwnerWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed

  def perform(host_id, login)
    Host.find_by_id(host_id).try(:sync_owner, login)
  end
end