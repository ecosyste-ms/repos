class PackageUsage < ApplicationRecord

  validates :ecosystem, presence: true
  validates :name, presence: true, format: { with: /\w/ }

  scope :with_package_metadata, -> { where('length(package::text) > 2 ') }
  scope :with_repo_metadata, -> { with_package_metadata.where("length(package ->> 'repo_metadata') > 2") }
  scope :host, ->(host_name) { where("package -> 'repo_metadata' -> 'host' ->> 'name' = ?", host_name.to_s) }
  scope :repo_uuid, ->(repo_uuid) { where("package -> 'repo_metadata' ->> 'uuid' = ?", repo_uuid.to_s) }

  has_many :repository_usages, dependent: :destroy
  has_many :repositories, through: :repository_usages

  def fetch_dependents_count
    @dependents_count ||= Dependency.where(ecosystem: ecosystem, package_name: name).distinct.count(:repository_id)
  end

  def update_dependents_count
    update_columns({dependents_count: fetch_dependents_count})
  end

  def registry
    @registry ||= Registry.find_by_ecosystem(ecosystem)
  end

  def packages_html_url
    return nil unless registry
    "#{PACKAGES_DOMAIN}/registries/#{registry.name.gsub(' ', '%20')}/packages/#{name}"
  end

  def packages_api_url
    return nil unless registry
    "#{PACKAGES_DOMAIN}/api/v1/registries/#{registry.name.gsub(' ', '%20')}/packages/#{name}"
  end

  def sync
    if registry.nil?
      update_columns(package_last_synced_at: Time.now)
      update_repository_usages_count
      return
    end
    response = Faraday.get(packages_api_url)
    if response.success?
      update_columns(package: JSON.parse(response.body), package_last_synced_at: Time.now)
    else
      update_columns(package_last_synced_at: Time.now)  
    end
    sync_repository_async if package
    update_repository_usages_count
  rescue
    update_columns(package_last_synced_at: Time.now) # swallow errors for now
  end

  def sync_async
    return if package_last_synced_at && package_last_synced_at > 1.day.ago
    PackageUsageSyncWorker.perform_async(id)
  end

  def self.sync_packages
    PackageUsage.order('package_last_synced_at asc nulls first').limit(5000).each(&:sync)
  end

  # TODO usages need to be updated after dependency updates

  def repo_metadata
    return {} unless package
    package['repo_metadata']
  end

  def repository
    return nil unless host
    @repository ||= host.find_repository(repo_metadata['full_name'].downcase)
  end

  def sync_repository
    return unless host
    host.sync_repository(repo_metadata['full_name'])
  end

  def sync_repository_async
    return unless host
    host.sync_repository_async(repo_metadata['full_name'])    
  end

  def host
    return nil unless repo_metadata
    return nil unless repo_metadata['host'] && repo_metadata['host']['name']
    @host ||= Host.find_by_name(repo_metadata['host']['name'])
  end

  def funding_links
    (package_funding_links + repo_funding_links + owner_funding_links).uniq
  end

  def package_metadata
    package['metadata'] || {}
  end

  def package_funding_links
    return [] if  package_metadata["funding"].blank?
    funding_array = package_metadata["funding"].is_a?(Array) ? package_metadata["funding"] : [package_metadata["funding"]] 
    funding_array.map{|f| f.is_a?(Hash) ? f['url'] : f }
  end

  def owner_funding_links
    return [] if repo_metadata.blank? || repo_metadata['owner_record'].blank? ||  repo_metadata['owner_record']["metadata"].blank?
    return [] unless repo_metadata['owner_record']["metadata"]['has_sponsors_listing']
    ["https://github.com/sponsors/#{repo_metadata['owner_record']['login']}"]
  end

  def repo_funding_links
    return [] if repo_metadata.blank? || repo_metadata['metadata'].blank? ||  repo_metadata['metadata']["funding"].blank?
    return [] if repo_metadata['metadata']["funding"].is_a?(String)
    repo_metadata['metadata']["funding"].map do |key,v|
      next if v.blank?
      case key
      when "github"
        Array(v).map{|username| "https://github.com/sponsors/#{username}" }
      when "tidelift"
        "https://tidelift.com/funding/github/#{v}"
      when "community_bridge"
        "https://funding.communitybridge.org/projects/#{v}"
      when "issuehunt"
        "https://issuehunt.io/r/#{v}"
      when "open_collective"
        "https://opencollective.com/#{v}"
      when "ko_fi"
        "https://ko-fi.com/#{v}"
      when "liberapay"
        "https://liberapay.com/#{v}"
      when "custom"
        v
      when "otechie"
        "https://otechie.com/#{v}"
      when "patreon"
        "https://patreon.com/#{v}"
      when "polar"
        "https://polar.sh/#{v}"
      when 'buy_me_a_coffee'
        "https://buymeacoffee.com/#{v}"
      else
        v
      end
    end.flatten.compact
  end

  def update_repository_usages
    RepositoryUsage.from_package_usage(self)
  end

  def update_repository_usages_count
    ruc = RepositoryUsage.count_for_package_usage(self)
    updates = {
      repository_usages_count: ruc
    }
    if ruc > dependents_count
      updates[:dependents_count] = ruc
    end
    update_columns(updates)
  end
end
