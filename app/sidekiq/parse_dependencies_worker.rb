class ParseDependenciesWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, queue: 'dependencies'

  def perform(repository_id)
    Repository.find_by_id(repository_id).try(:parse_dependencies)
  end
end