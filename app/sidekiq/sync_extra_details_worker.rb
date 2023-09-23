class SyncExtraDetailsWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, queue: 'extra'

  def perform(repository_id)
    Repository.find_by_id(repository_id).try(:sync_extra_details)
  end
end
