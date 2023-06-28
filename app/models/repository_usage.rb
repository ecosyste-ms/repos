class RepositoryUsage < ApplicationRecord
  validates :repository_id, presence: true
  validates :package_usage_id, presence: true

  belongs_to :repository
  belongs_to :package_usage

  def self.crawl
    latest_id = REDIS.get('repository_usage_crawl_id').to_i

    Repository.where('id > ?', latest_id).find_each do |repository|
      from_repository(repository)
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

    existing_package_usages = PackageUsage.where(key: unique_dependencies.map{|ecosystem, package_name| "#{ecosystem}:#{package_name}"})

    package_usages = unique_dependencies.map do |ecosystem, package_name|
      existing_package_usages.find{|pu| pu.key == "#{ecosystem}:#{package_name}"} || PackageUsage.where(ecosystem: ecosystem, name: package_name, key: "#{ecosystem}:#{package_name}").first_or_create!
    end

    rus = package_usages.map do |package_usage|
      {repository_id: repository.id, package_usage_id: package_usage.id}
    end.compact

    RepositoryUsage.upsert_all(rus) if rus.any?
  end

  def self.count_for_package_usage(package_usage)
    RepositoryUsage.where(package_usage_id: package_usage.id).count
  end
end
