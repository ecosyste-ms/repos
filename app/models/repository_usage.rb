class RepositoryUsage < ApplicationRecord
  validates :repository_id, presence: true
  validates :package_usage_id, presence: true

  belongs_to :repository
  belongs_to :package_usage

  def self.crawl
    latest_id = REDIS.get('repository_usage_crawl_id').to_i

    Repository.where('id > ?', latest_id).find_each do |repository|
      next if repository.dependencies_parsed_at.nil?
      next if repository.usage_last_calculated.present?
      from_repository(repository) rescue nil
      REDIS.set('repository_usage_crawl_id', repository.id)
    end
  end

  def self.from_repository(repository)
    return if repository.dependencies_parsed_at.nil?
    # TODO deleting everything for the repo may be wasteful
    RepositoryUsage.where(repository: repository).delete_all

    unique_dependencies = Set.new
    repository.manifests.includes(:dependencies).each do |manifest|
      manifest.dependencies.each do |dependency|
        unique_dependencies.add([dependency.ecosystem, dependency.package_name])
      end
    end

    keys = unique_dependencies.map{|ecosystem, package_name| "#{ecosystem}:#{package_name}"}.uniq

    existing_package_usages = []
    keys.each_slice(50) do |slice|
      existing_package_usages << PackageUsage.where(key: slice).all
    end
    existing_package_usages.flatten!

    package_usages = unique_dependencies.map do |ecosystem, package_name|
      if package_name.match(/\w/)
        existing_package_usages.find{|pu| pu.key == "#{ecosystem}:#{package_name}"} || PackageUsage.where(ecosystem: ecosystem, name: package_name, key: "#{ecosystem}:#{package_name}").first_or_create!
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
    repo_ids = Set.new
    Dependency.where(ecosystem: package_usage.ecosystem, package_name: package_usage.name).includes(:repository).each_instance do |dependency|
      if dependency.repository.nil?
        puts "nil repo #{dependency.id}"
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
        puts "usage_last_calculated #{dependency.repository.full_name}"
        next
      end
      if dependency.repository.dependencies_parsed_at.nil?
        puts "dependencies_parsed_at nil #{dependency.repository.full_name}"
      end

      puts "from_package_usage #{dependency.repository.full_name}"
      RepositoryUsage.from_repository(dependency.repository)
    end
  end
end
