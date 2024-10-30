class ParseDependenciesWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'dependencies', lock: :until_executed

  def perform(repository_id)
    Repository.includes(manifests: :dependencies).find_by_id(repository_id).try(:parse_dependencies)
  end
end