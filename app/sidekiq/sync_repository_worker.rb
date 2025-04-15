class SyncRepositoryWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(host_id, full_name)
    Host.find_by_id(host_id).try(:sync_repository, full_name)
  end
end