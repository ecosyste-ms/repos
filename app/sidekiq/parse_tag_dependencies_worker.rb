class ParseTagDependenciesWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, queue: 'dependencies'

  def perform(tag_id)
    Tag.includes(manifests: :dependencies).find_by_id(tag_id).try(:parse_dependencies)
  end
end