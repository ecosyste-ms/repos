class ParseTagDependenciesWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'dependencies', lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(tag_id)
    Tag.includes(manifests: :dependencies).find_by_id(tag_id).try(:parse_dependencies)
  end
end