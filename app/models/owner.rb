class Owner < ApplicationRecord
  belongs_to :host
  counter_culture :host, execute_after_commit: true

  validates :login, presence: true

  scope :created_after, ->(date) { where('created_at > ?', date) }
  scope :updated_after, ->(date) { where('updated_at > ?', date) }

  scope :kind, ->(kind) { where(kind: kind) }
  enum kind: { user: 'user', organization: 'organization' }

  scope :has_sponsors_listing, -> { where("metadata->>'has_sponsors_listing' = 'true'") }
  
  def self.sync_least_recently_synced
    Owner.order('last_synced_at asc nulls first').includes(:host).limit(2500).each(&:sync_async)
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
    @related_dot_github_repo ||= host.repositories.find_by('lower(full_name) = ?', "#{login.downcase}/.github")
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
      when "polar"
        "https://polar.sh/#{v}"
      when 'buy_me_a_coffee'
        "https://buymeacoffee.com/#{v}"
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
    update_column(:repositories_count, fetch_repositories_count)
  end

  def update_total_stars
    update_column(:total_stars, fetch_total_stars)
  end

  def fetch_repositories_count
    repositories.each_instance.inject(0) { |repos, _| repos + 1 }
  end

  def fetch_total_stars
    repositories.each_instance.sum(&:stargazers_count)
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
