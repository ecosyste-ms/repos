class PingPackagesWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default, lock: :until_executed

  def perform(repo_id)
    Repository.find_by_id(repo_id).try(:ping_packages)
  end
end
