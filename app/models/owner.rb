class Owner < ApplicationRecord
  belongs_to :host

  validates :login, presence: true

  scope :created_after, ->(date) { where('created_at > ?', date) }
  scope :updated_after, ->(date) { where('updated_at > ?', date) }
  
  def self.sync_least_recently_synced
    Owner.order('last_synced_at asc nulls first').where('last_synced_at is null or last_synced_at < ?', 1.day.ago).includes(:host).limit(1000).each(&:sync_async)
  end

  def to_s
    name.presence || login
  end

  def to_param
    login
  end

  def repositories
    host.repositories.where(owner: login)
  end
  
  def sync
    host.sync_owner(login)
  end

  def sync_async
    SyncOwnerWorker.perform_async(host_id, login)
  end

  def related_dot_github_repo
    return unless host.kind == 'github'
    @related_dot_github_repo ||= host.find_repository("#{login}/.github")
  end

  def funding_links
    if yaml_funding_links
      yaml_funding_links
    else
      metadata['has_sponsors_listing'] ? ["https://github.com/sponsors/#{login}"] : []
    end
  end

  def yaml_funding_links
    return unless related_dot_github_repo.present? 
    return unless related_dot_github_repo.metadata['funding'].present?
    metadata['funding'] = related_dot_github_repo.metadata['funding']
    return [] if metadata.blank? ||  metadata["funding"].blank?
    return [] unless metadata["funding"].is_a?(Hash)
    metadata["funding"].map do |key,v|
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
      else
        v
      end
    end.flatten.compact
  end

  def html_url
    "#{host.url}/#{login}"
  end

  def icon_url
    avatar_url
  end

  def update_repositories_count
    update_column(:repositories_count, repositories.count)
  end

  def sync_repositories
    host.sync_owner_repositories_async(self)
  end

  def check_status
    status = Faraday.head(html_url).status
    return if status == 200
    if status == 404
      repositories.each(&:sync_async)
      destroy
    elsif [301, 302].include?(status)
      sync_async
    end
  end
end
