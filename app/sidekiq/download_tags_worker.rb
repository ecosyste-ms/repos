class DownloadTagsWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, queue: 'tags'

  def perform(repository_id)
    Repository.find_by_id(repository_id).try(:download_tags)
  end
end