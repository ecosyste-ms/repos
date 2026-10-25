class RepositoryUsage < ApplicationRecord
  MAX_MANIFESTS_PER_READ = 1_000
  MAX_RAW_DEPENDENCIES = 1_000
  MAX_PACKAGES_PER_READ = 10_000

  class ReadLimitExceeded < StandardError; end
  class InvalidContribution < StandardError; end

  validates :repository_id, presence: true
  validates :package_usage_id, presence: true

  belongs_to :repository
  belongs_to :package_usage

  def self.generation
    value = ENV['REPOSITORY_USAGE_GENERATION']
    Integer(value, 10) if value&.match?(/\A[1-9]\d*\z/)
  end

  def self.writes_enabled?(repository_id = nil)
    return false unless ENV['REPOSITORY_USAGE_WRITES_ENABLED'] == 'true' && generation

    ids = ENV['REPOSITORY_USAGE_REPOSITORY_IDS'].to_s.split(',').map(&:strip)
    ids.empty? || ids.include?(repository_id.to_s)
  end

  def self.packages_for_repository(repository, max_manifests: MAX_MANIFESTS_PER_READ, max_packages: MAX_PACKAGES_PER_READ)
    manifest_ids = Manifest.where(repository_id: repository.id, tag_id: nil).limit(max_manifests + 1).pluck(:id)
    if manifest_ids.length > max_manifests
      raise ReadLimitExceeded, "Repository #{repository.id} exceeds the #{max_manifests} manifest read limit"
    end
    return [] if manifest_ids.empty?

    dependencies = Dependency.where(manifest_id: manifest_ids)
    packages = dependencies.limit(MAX_RAW_DEPENDENCIES + 1).pluck(:ecosystem, :package_name)
    if packages.length > MAX_RAW_DEPENDENCIES
      packages = dependencies.distinct.limit(max_packages + 1).pluck(:ecosystem, :package_name)
      if packages.length > max_packages
        raise ReadLimitExceeded, "Repository #{repository.id} exceeds the #{max_packages} package read limit"
      end
    end

    packages.uniq
  end

  def self.crawl
    RepositoryUsageBackfillWorker.perform_async(generation) if writes_enabled?
  end

  def self.from_repository(repository, max_manifests: MAX_MANIFESTS_PER_READ, max_packages: MAX_PACKAGES_PER_READ, statement_timeout: '2s')
    return unless repository && writes_enabled?(repository.id)

    transaction(isolation: :repeatable_read) do
      connection.execute("SET LOCAL statement_timeout = #{connection.quote(statement_timeout)}")
      connection.execute("SET LOCAL lock_timeout = '250ms'")
      connection.execute('SET LOCAL jit = off')
      connection.execute('SET LOCAL max_parallel_workers_per_gather = 0')
      lock_repository(repository.id)
      repository = Repository.select(:id, :dependencies_parsed_at, :usage_count_generation, :usage_updated_at, :usage_last_calculated).find_by(id: repository.id)
      next unless repository&.dependencies_parsed_at
      raise InvalidContribution, 'Repository belongs to a newer generation' if repository.usage_count_generation.to_i > generation

      if repository.usage_count_generation == generation && repository.usage_last_calculated && (!repository.usage_updated_at || repository.usage_updated_at == repository.usage_last_calculated)
        next true
      end
      packages = packages_for_repository(repository, max_manifests: max_manifests, max_packages: max_packages)
      contributed = reconcile(repository, packages, max_packages: max_packages)
      repository.update_columns(usage_count_generation: generation, usage_last_calculated: repository.usage_updated_at || Time.current) if contributed
      true
    end
  end

  def self.remove_repository(repository)
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(138132, #{Integer(repository.id)})")
      target = Repository.where(id: repository.id).pick(:usage_count_generation)
      next unless target

      ids = where(repository_id: repository.id).distinct.pluck(:package_usage_id)
      rows = PackageUsage.where(id: ids, usage_count_generation: target).order(:id).lock.pluck(:id, :repository_usages_count)
      raise InvalidContribution, 'Missing recorded contribution' if rows.any? { |_, count| count.nil? || count < 1 }

      rows.map(&:first).each_slice(1_000) do |slice|
        PackageUsage.where(id: slice).update_all(['repository_usages_count = repository_usages_count - 1, updated_at = ?', Time.current])
      end
    end
  end

  def self.lock_repository(repository_id)
    # Transaction locks are safe with PgBouncer transaction pooling.
    locked = connection.select_value("SELECT pg_try_advisory_xact_lock(138132, #{Integer(repository_id)})")
    raise ActiveRecord::LockWaitTimeout, "Usage maintenance already running for repository #{repository_id}" unless locked
  end

  def self.reconcile(repository, packages, max_packages: MAX_PACKAGES_PER_READ)
    usages = where(repository_id: repository.id)
    old_ids = usages.limit(max_packages + 1).pluck(:package_usage_id)
    raise ReadLimitExceeded, "Repository #{repository.id} exceeds the relationship read limit" if old_ids.length > max_packages

    package_rows = packages.filter_map do |ecosystem, name|
      next if ecosystem.blank? || name.blank? || !name.match?(/\w/)
      { ecosystem: ecosystem, name: name, key: "#{ecosystem}:#{name}", dependents_count: 0, repository_usages_count: 0 }
    end
    new_ids = []
    package_rows.each_slice(1_000) do |rows|
      keys = rows.pluck(:key)
      existing = PackageUsage.where(key: keys).pluck(:key, :id).to_h
      missing = rows.reject { |row| existing.key?(row[:key]) }
      PackageUsage.insert_all(missing, unique_by: :index_package_usages_on_key) if missing.any?
      new_ids.concat(PackageUsage.where(key: keys).pluck(:id))
    end

    additions = new_ids.uniq - old_ids
    removals = old_ids.uniq - new_ids
    counted = repository.usage_count_generation == generation
    changes = if counted
      additions.to_h { |id| [id, 1] }.merge(removals.to_h { |id| [id, -1] })
    else
      new_ids.uniq.to_h { |id| [id, 1] }
    end

    change_counts(changes) if changes.any?
    usages.where(package_usage_id: removals).delete_all if removals.any?
    insert_all!(additions.map { |id| { repository_id: repository.id, package_usage_id: id } }) if additions.any?
    counted || new_ids.any?
  end

  def self.change_counts(changes)
    counts = PackageUsage.where(id: changes.keys).order(:id).lock.pluck(:id, :usage_count_generation, :repository_usages_count)
    raise InvalidContribution, 'Missing package' unless counts.length == changes.length

    counts.group_by do |id, recorded_generation, count|
      fresh = recorded_generation != generation
      total = fresh ? 0 : count
      raise InvalidContribution, 'Invalid recorded contribution' if recorded_generation.to_i > generation || total.nil? || total + changes.fetch(id) < 0
      [fresh, changes.fetch(id)]
    end.each do |(fresh, delta), rows|
      scope = PackageUsage.where(id: rows.map(&:first))
      if fresh
        scope.update_all(usage_count_generation: generation, repository_usages_count: delta, updated_at: Time.current)
      else
        scope.update_all(['repository_usages_count = repository_usages_count + ?, updated_at = ?', delta, Time.current])
      end
    end
  end

  def self.count_for_package_usage(package_usage)
    # TODO(DB_PERF): count_for_package_usage disabled 2026-01-11
    # COUNT on 10B+ row table is slow
    return nil
    RepositoryUsage.where(package_usage_id: package_usage.id).count
  end

  def self.from_package_usage(package_usage)
    # TODO(DB_PERF): from_package_usage disabled 2026-01-10
    # each_instance over potentially millions of dependencies per package
    # Needs pagination/limits or background processing with throttling
    return
    repo_ids = Set.new
    Dependency.where(ecosystem: package_usage.ecosystem, package_name: package_usage.name).includes(:repository).each_instance do |dependency|
      if dependency.repository.nil?
        if dependency.manifest
          dependency.manifest.destroy
        else
          dependency.destroy
        end
        next
      end
      next if repo_ids.include?(dependency.repository_id)
      repo_ids.add(dependency.repository_id)
      if dependency.repository.usage_last_calculated.present?
        next
      end
      if dependency.repository.dependencies_parsed_at.nil?
      end

      unless dependency.repository.fork?
        RepositoryUsage.from_repository(dependency.repository)
      end
    end
  end
end
