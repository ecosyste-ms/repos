class PackageUsageWorker
  include Sidekiq::Worker

  def perform(repository_id)
    r = Repository.includes(manifests: :dependencies).find_by_id(repository_id)
    PackageUsage.aggregate_dependencies_for_repo(r) if r
  end
end