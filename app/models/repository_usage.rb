class RepositoryUsage < ApplicationRecord
  validates :repository_id, presence: true
  validates :package_usage_id, presence: true

  belongs_to :repository
  belongs_to :package_usage

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
    # TODO(DB_PERF): from_repository disabled 2026-01-10
    # Queries 24B dependencies table with joins, deletes from 10B repository_usages table
    # Needs query optimization or complete rethink of approach at this scale
    return
    return if repository.dependencies_parsed_at.nil?
    # TODO deleting everything for the repo may be wasteful
    RepositoryUsage.where(repository: repository).delete_all

    unique_dependencies = Dependency
      .joins(:manifest)
      .where(manifests: { repository_id: repository.id })
      .distinct
      .pluck(:ecosystem, :package_name)

    keys = unique_dependencies.map { |ecosystem, package_name| "#{ecosystem}:#{package_name}" }

    existing_package_usages = []
    keys.each_slice(1000) do |slice|
      existing_package_usages.concat(PackageUsage.where(key: slice).to_a)
    end

    package_usages = unique_dependencies.map do |ecosystem, package_name|
      if package_name.match(/\w/)
        begin
          existing_package_usages.find{|pu| pu.key == "#{ecosystem}:#{package_name}"} || PackageUsage.where(ecosystem: ecosystem, name: package_name, key: "#{ecosystem}:#{package_name}").first_or_create!
        rescue PG::UniqueViolation
          # duplicate key
        end
      else
        nil
      end
    end.compact

    rus = package_usages.map do |package_usage|
      {repository_id: repository.id, package_usage_id: package_usage.id}
    end.compact

    RepositoryUsage.upsert_all(rus) if rus.any?
    repository.update_columns(usage_last_calculated: Time.now)
  end

  def self.count_for_package_usage(package_usage)
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
