class PingPackagesWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default

  def perform(repo_id)
    Repository.find_by_id(repo_id).try(:ping_packages)
  end
end
