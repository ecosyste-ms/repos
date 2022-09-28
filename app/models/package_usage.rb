class PackageUsage < ApplicationRecord
  def self.aggregate_dependencies(limit = 1_000_000)
    start_id = REDIS.get('package_usage_id') || 0
    end_id = start_id.to_i + limit

    Dependency.where('id > ?', start_id).where('id < ?', end_id).find_each do |dependency|
      PackageUsage.find_or_create_by!(ecosystem: dependency.ecosystem.downcase, name: dependency.package_name).tap do |package_usage|
        package_usage.repo_ids |= [dependency.repository_id]
        package_usage.dependents_count = package_usage.repo_ids.length
        package_usage.requirements[dependency.requirements] ||= 0
        package_usage.requirements[dependency.requirements] += 1 
        package_usage.kind[dependency.kind] ||= 0
        package_usage.kind[dependency.kind] += 1

        direct = dependency.direct ? 'direct' : 'transitive'
        package_usage.direct[direct] ||= 0
        package_usage.direct[direct] += 1
        package_usage.save!
      end
      REDIS.set('package_usage_id', dependency.id)
    end
  end

  # TODO sync some details in from packages.ecosyste.ms

  def dependent_repos
    Repository.where(id: repo_ids)
  end
end
