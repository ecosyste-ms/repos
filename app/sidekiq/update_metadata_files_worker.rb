class UpdateMetadataFilesWorker
  include Sidekiq::Worker
  #sidekiq_options lock: :until_executed

  def perform(repo_id)
    Repository.find_by_id(repo_id).try(:update_metadata_files)
  end
end