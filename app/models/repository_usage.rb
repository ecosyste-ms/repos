class RepositoryUsage < ApplicationRecord
  MAX_MANIFESTS_PER_READ = 1_000
  MAX_RAW_DEPENDENCIES = 1_000
  MAX_PACKAGES_PER_READ = 10_000

  class ReadLimitExceeded < StandardError; end
  class CounterBaselineRequired < StandardError; end

  validates :repository_id, presence: true
  validates :package_usage_id, presence: true

  belongs_to :repository
  belongs_to :package_usage

  def self.writes_enabled?(repository_id)
    return false unless ENV['REPOSITORY_USAGE_WRITES_ENABLED'] == 'true'

    ids = ENV['REPOSITORY_USAGE_REPOSITORY_IDS'].to_s.split(',').map(&:strip)
    ids.empty? || ids.include?(repository_id.to_s)
  end

  def self.packages_for_repository(repository)
    manifest_ids = Manifest.where(repository_id: repository.id, tag_id: nil).limit(MAX_MANIFESTS_PER_READ + 1).pluck(:id)
    if manifest_ids.length > MAX_MANIFESTS_PER_READ
      raise ReadLimitExceeded, "Repository #{repository.id} exceeds the #{MAX_MANIFESTS_PER_READ} manifest read limit"
    end
    return [] if manifest_ids.empty?

    dependencies = Dependency.where(manifest_id: manifest_ids)
    packages = dependencies.limit(MAX_RAW_DEPENDENCIES + 1).pluck(:ecosystem, :package_name)
    if packages.length > MAX_RAW_DEPENDENCIES
      packages = dependencies.distinct.limit(MAX_PACKAGES_PER_READ + 1).pluck(:ecosystem, :package_name)
      if packages.length > MAX_PACKAGES_PER_READ
        raise ReadLimitExceeded, "Repository #{repository.id} exceeds the #{MAX_PACKAGES_PER_READ} package read limit"
      end
    end

    packages.uniq
  end

  def self.crawl
    # TODO(DB_PERF): crawl disabled 2026-01-10
    # Iterates all 297M repositories with find_each, calls from_repository on each
    # Needs batching with limits, or move to scheduled background job with throttling
    return
    latest_id = REDIS.get('repository_usage_crawl_id').to_i

    Repository.where('id > ?', latest_id).find_each do |repository|
      next if repository.dependencies_parsed_at.nil?
      next if repository.usage_last_calculated.present?
      from_repository(repository) rescue nil
      REDIS.set('repository_usage_crawl_id', repository.id)
    end
  end

  def self.from_repository(repository)
    return unless repository && writes_enabled?(repository.id)

    transaction(isolation: :repeatable_read) do
      connection.execute("SET LOCAL statement_timeout = '2s'")
      connection.execute("SET LOCAL lock_timeout = '250ms'")
      connection.execute('SET LOCAL jit = off')
      connection.execute('SET LOCAL max_parallel_workers_per_gather = 0')
      lock_repository(repository.id)
      repository = Repository.select(:id, :dependencies_parsed_at).find_by(id: repository.id)
      next unless repository&.dependencies_parsed_at

      reconcile(repository, packages_for_repository(repository))
      repository.update_columns(usage_last_calculated: Time.current)
    end
  end

  def self.remove_repository(repository)
    return unless writes_enabled?(repository.id)

    transaction do
      lock_repository(repository.id)
      reconcile(repository, [])
    end
  end

  def self.lock_repository(repository_id)
    # Transaction locks are safe with PgBouncer transaction pooling.
    locked = connection.select_value("SELECT pg_try_advisory_xact_lock(138132, #{Integer(repository_id)})")
    raise ActiveRecord::LockWaitTimeout, "Usage maintenance already running for repository #{repository_id}" unless locked
  end

  def self.reconcile(repository, packages)
    usages = where(repository_id: repository.id)
    old_ids = usages.limit(MAX_PACKAGES_PER_READ + 1).pluck(:package_usage_id)
    raise ReadLimitExceeded, "Repository #{repository.id} exceeds the relationship read limit" if old_ids.length > MAX_PACKAGES_PER_READ

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
    changes = additions.to_h { |id| [id, 1] }.merge(removals.to_h { |id| [id, -1] })
    return if changes.empty?

    change_counts(changes)
    usages.where(package_usage_id: removals).delete_all if removals.any?
    insert_all!(additions.map { |id| { repository_id: repository.id, package_usage_id: id } }) if additions.any?
  end

  def self.change_counts(changes)
    counts = PackageUsage.where(id: changes.keys).order(:id).lock.pluck(:id, :dependents_count, :repository_usages_count)
    invalid = counts.find do |id, dependents, usages|
      dependents.nil? || usages.nil? || dependents != usages || dependents + changes.fetch(id) < 0
    end
    if invalid || counts.length != changes.length
      raise CounterBaselineRequired, 'Usage counters need a consistent baseline before applying membership changes'
    end

    changes.group_by { |id, delta| delta }.each do |delta, entries|
      PackageUsage.where(id: entries.map(&:first)).update_all([
        'dependents_count = dependents_count + ?, repository_usages_count = repository_usages_count + ?, updated_at = ?',
        delta, delta, Time.current
      ])
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
