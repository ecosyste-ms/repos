class PackageUsage < ApplicationRecord
  def self.aggregate_dependencies(limit = 1_000_000)
    start_id = REDIS.get('package_usage_id') || 0
    end_id = start_id.to_i + limit

    Dependency.where('id > ?', start_id).where('id < ?', end_id).find_each do |dependency|
      PackageUsage.find_or_create_by!(ecosystem: dependency.ecosystem.downcase, name: dependency.package_name).tap do |package_usage|
        package_usage.repo_ids |= [dependency.repository_id]
        package_usage.dependents_count = package_usage.repo_ids.length
        package_usage.requirements[dependency.requirements] ||= 0
        package_usage.requirements[dependency.requirements] += 1 # TODO split into direct vs transitive
        package_usage.kind[dependency.kind] ||= 0
        package_usage.kind[dependency.kind] += 1 # TODO this may be too large

        direct = dependency.direct ? 'direct' : 'transitive'
        package_usage.direct[direct] ||= 0
        package_usage.direct[direct] += 1 # TODO this may be too large
        package_usage.save!
      end
      REDIS.set('package_usage_id', dependency.id)
    end
  end

  def self.aggregate_dependencies_for_repo(repository)
    deps = {}

    repository.manifests.sort_by(&:kind).each do |manifest|
      manifest.dependencies.each do |d|
        deps[d.ecosystem] ||= {}
        deps[d.ecosystem][d.package_name] ||= {}
        deps[d.ecosystem][d.package_name][:requirements] ||= []
        deps[d.ecosystem][d.package_name][:requirements] |= [d.requirements]
        deps[d.ecosystem][d.package_name][:kind] ||= []
        deps[d.ecosystem][d.package_name][:kind] |= [d.kind]
        deps[d.ecosystem][d.package_name][:direct] ||= []
        deps[d.ecosystem][d.package_name][:direct] |= [d.direct]
      end
    end

    deps.each do |ecosystem, packages|
      existing = PackageUsage.where(ecosystem: ecosystem, name: packages.keys).all
      packages.each do |package_name, data|
        if pu = existing.find { |p| p.name == package_name }
          next if pu.repo_ids.include?(repository.id)
          pu.repo_ids |= [repository.id]
          pu.dependents_count = pu.repo_ids.length
          
          data[:requirements].each do |req|
            pu.requirements[req] ||= 0
            pu.requirements[req] += 1
          end

          data[:kind].each do |kind|
            pu.kind[kind] ||= 0
            pu.kind[kind] += 1
          end
          
          data[:direct].each do |direct|
            pu.direct[direct] ||= 0
            pu.direct[direct] += 1
          end

          pu.save
        else
          PackageUsage.create({
            ecosystem: ecosystem,
            name: package_name,
            dependents_count: 1,
            repo_ids: [repository.id],
            requirements: { data[:requirements].first => 1 },
            kind: {data[:kind].first => 1},
            direct: {data[:direct].first => 1}
          })
        end
      end
    end
    repository.update_column(:usage_updated_at, Time.now)
  end

  # TODO sync some details in from packages.ecosyste.ms

  # TODO usages need to be updated after dependency updates

  def dependent_repos
    Repository.where(id: repo_ids).includes(:host)
  end
end
