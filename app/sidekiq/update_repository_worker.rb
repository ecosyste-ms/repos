class UpdateRepositoryWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed

  def perform(repo_id)
    Repository.find_by_id(repo_id).try(:sync)
  end
end