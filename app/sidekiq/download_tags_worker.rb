class DownloadTagsWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'tags', lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(repository_id)
    Repository.find_by_id(repository_id).try(:download_tags)
  end
end