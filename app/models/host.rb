class Host < ApplicationRecord
  validates_presence_of :name, :url, :kind
  validates_uniqueness_of :name, :url

  has_many :repositories
  has_many :owners

  scope :kind, ->(kind) { where(kind: kind) }

  def topics
    Rails.cache.fetch("host/#{self.id}/topics", expires_in: 1.week) do
      Repository.connection.select_rows("SELECT topics, COUNT(topics) AS topics_count FROM (SELECT id, unnest(topics) AS topics FROM repositories WHERE host_id = #{self.id} AND topics IS NOT NULL AND array_length(topics, 1) > 0) AS foo GROUP BY topics ORDER BY topics_count DESC, topics ASC LIMIT 50000;")
    end
  end

  def self.find_by_name(name)
    return nil if name.blank?
    host = Host.find_by('lower(name) = ?', name.downcase)
  end

  def self.find_by_name!(name)
    return nil if name.blank?
    host = Host.find_by('lower(name) = ?', name.downcase)
    raise ActiveRecord::RecordNotFound if host.nil?
    host
  end

  def find_repository(full_name)
    return nil if full_name.blank?
    repo = repositories.find_by('lower(full_name) = ?', full_name.downcase)
    repo = repositories.where('previous_names && ARRAY[?]::varchar[]', full_name.downcase).to_a.first if repo.nil?
    repo
  end

  def self.find_by_domain(domain)
    Host.all.find { |host| host.domain == domain }
  end

  def to_s
    name
  end

  def to_param
    name
  end

  def domain
    Addressable::URI.parse(url).host
  end

  def icon
    org || host_instance.icon
  end

  def display_kind?
    return false if name.split('.').length == 2 && name.split('.').first.downcase == kind
    name.downcase != kind
  end

  def sync_repository_async(full_name)
    SyncRepositoryWorker.perform_async(id, full_name)
  end

  def sync_repository(full_name, uuid: nil)
    return if full_name.blank?
    # remove .git from the end of the full_name
    full_name = full_name.gsub(/\.git$/, '')
    puts "syncing #{full_name}"
    repo = repositories.find_by('lower(full_name) = ?', full_name.downcase)

    if repo
      repo.sync
    else
      repo_hash = host_instance.fetch_repository(uuid || full_name)
      return if repo_hash.blank?

      ActiveRecord::Base.transaction do
        repo = repositories.find_by(uuid: repo_hash[:uuid]) if repo_hash[:uuid].present?
        repo = repositories.new(uuid: repo_hash[:id], full_name: repo_hash[:full_name]) if repo.nil?
        repo.full_name = repo_hash[:full_name] if repo.full_name.downcase != repo_hash[:full_name].downcase

        repo.previous_names = (repo.previous_names + [full_name.downcase]).uniq if repo.full_name_changed? || repo.full_name.downcase != full_name.downcase

        repo.assign_attributes(repo_hash)
        repo_changed = repo.changed?
        repo.last_synced_at = Time.now
        if repo.pushed_at_changed?
          repo.files_changed = true
        end
        repo.save
        repo.ping_packages_async if repo_changed && repo.persisted?
        repo.sync_extra_details_async if !repo.fork? && repo_changed && repo.persisted? && repo.files_changed?
        repo.sync_owner
        repo
      end
    end
  rescue *Array(host_class::IGNORABLE_EXCEPTIONS) => e
    p e
    nil
  rescue *Array(host_class.api_missing_error_class) => e
    p e
    nil
  rescue ActiveRecord::RecordNotUnique => e
    p e
    nil
  end

  def sync_recently_changed_repos(since = 15.minutes)
    host_instance.recently_changed_repo_names(since).first(1000).each do |full_name|
      sync_repository(full_name)
    end
  end

  def sync_recently_changed_repos_async(since = 15.minutes)
    host_instance.recently_changed_repo_names(since).first(1000).each do |full_name|
      sync_repository_async(full_name)
    end
  end 

  def sync_owner_repositories_async(owner)
    names = host_instance.load_owner_repos_names(owner)
    names.each do |full_name|
      sync_repository_async(full_name)
    end
  end

  def sync_owner_repositories(owner)
    names = host_instance.load_owner_repos_names(owner)
    names.each do |full_name|
      sync_repository(full_name)
    end
  end

  def crawl_repositories_async
    host_instance.crawl_repositories_async
  end

  def crawl_repositories
    host_instance.crawl_repositories
  end

  def download_tags(repository)
    host_instance.download_tags(repository)
    repository.set_latest_tag_published_at
    repository.set_latest_tag_name
    repository.save if repository.changed?
  end

  def download_releases(repository)
    host_instance.download_releases(repository)
  end

  def get_file_contents(repository, path)
    host_instance.get_file_contents(repository, path)
  end

  def get_file_list(repository)
    host_instance.get_file_list(repository)
  end

  def html_url(repository)
    host_instance.html_url(repository)
  end

  def tag_url(repository, tag_name)
    host_instance.tag_url(repository, tag_name)
  end

  def download_url(repository, branch = nil, kind = 'branch')
    host_instance.download_url(repository, branch, kind)
  end

  def avatar_url(repository, size)
    host_instance.avatar_url(repository, size)
  end

  def blob_url(repository, sha)
    host_instance.blob_url(repository, sha)
  end

  def host_class
    "Hosts::#{kind.capitalize}".constantize
  end

  def host_instance
    host_class.new(self)
  end

  def import_github_repos_from_timeline(id = nil)
    return unless kind == 'github'
    id = REDIS.get('last_timeline_id') if id.nil?
  
    url = "#{TIMELINE_DOMAIN}/api/v1/events?per_page=1000&event_type=PullRequestEvent"
    url = url + "&before=#{id}" if id
  
    begin
      puts "loading #{url}"
      resp = Faraday.get(url) do |req|
        req.options.timeout = 30
      end
  
      if resp.success?
        events = Oj.load(resp.body)
      else
        events = nil
      end

    rescue Faraday::Error
      events = nil
    end
  
    return unless events.present?
  
    events.each do |e| 
      hash = e['payload']['pull_request']['base']['repo'].to_hash.with_indifferent_access
      
      repo_hash = host_instance.map_repository_data(hash)
      next if repo_hash[:fork]
      repo = repositories.find_by(uuid: repo_hash[:uuid])
      repo = repositories.find_by('lower(full_name) = ?', repo_hash[:full_name].downcase) if repo.nil?
  
      next if repo && repo.last_synced_at && e['created_at'] < repo.last_synced_at
      next if repo && repo.full_name.downcase != repo_hash[:full_name].downcase
  
      if repo.nil?
        repo = repositories.new(uuid: repo_hash[:id], full_name: repo_hash[:full_name])
        puts "new repo: #{repo.full_name}"
      else
        puts "update:   #{repo.full_name}"
      end
  
      repo.assign_attributes(repo_hash)
      repo.last_synced_at = e['created_at']
      if repo.save
        repo.sync_async
      end
    rescue TypeError
      next
    end
  
    if events.any?
      next_id = events.last['id']
      puts "next id: #{next_id}" 
      REDIS.set('last_timeline_id', next_id)
      import_github_repos_from_timeline(next_id)
    end
  end

  def sync_owner(login)
    existing_owner = owners.find_by('lower(login) = ?', login)

    return existing_owner if existing_owner && existing_owner.last_synced_at && existing_owner.last_synced_at > 1.week.ago

    # Sync local information now as we can return early (no token, or no need to sync external data)
    if existing_owner
      existing_owner.repositories_count = existing_owner.fetch_repositories_count
      existing_owner.total_stars = existing_owner.fetch_total_stars
      existing_owner.save! if existing_owner.changed?
    end
    
    owner_hash = host_instance.fetch_owner(login)
    if owner_hash.nil? || owner_hash[:login].nil?
      owners.find_by('lower(login) = ?', login).try(:check_status)
      return nil
    end

    owner = owners.find_by(uuid: owner_hash[:uuid])
    owner = owners.find_by('lower(login) = ?', owner_hash[:login].downcase) if owner.nil?
    if owner.nil?
      owner = owners.new(uuid: owner_hash[:id], login: owner_hash[:login])
    end

    owner_hash.each do |key, value|
      owner_hash[key] = value.gsub("\u0000", "") if value.is_a?(String)
    end

    owner.assign_attributes(owner_hash)
    owner.last_synced_at = Time.now
    if owner.new_record?
      owner.repositories_count = owner.fetch_repositories_count
      owner.total_stars = owner.fetch_total_stars
    end
    owner.save!
    owner.sync_repositories
    owner
  rescue ActiveRecord::RecordNotUnique
    sync_owner_async(login) if owner.try(:destroy)
  end

  def check_owner_status(login)
    owner_hash = host_instance.fetch_owner(login)
    return nil if owner_hash.nil?
  end

  def check_owner_status_async(login)
    CheckOwnerStatusWorker.perform_async(id, login)
  end

  def sync_owner_async(login)
    SyncOwnerWorker.perform_async(id, login)
  end

  def missing_owner_names
    all_owner_names - existing_owner_names
  end

  def all_owner_names
    repositories.pluck(:owner).uniq
  end

  def existing_owner_names
    owners.pluck(:login)
  end

  def sync_missing_owners(limit = 100)
    missing_owner_names.first(limit).each do |login|
      sync_owner(login)
    end
  end

  def sync_missing_owners_async(limit = 100)
    missing_owner_names.first(limit).each do |login|
      sync_owner_async(login)
    end
  end

  def icon_url
    "https://github.com/#{icon}.png"
  end

  def kind_icon_url
    "https://github.com/#{host_instance.icon}.png"
  end

  def update_version
    version = host_instance.host_version
    update_columns(version: version) if version.present? 
  end

  def check_status
    return if url.blank?
    
    start_time = Time.current
    
    begin
      response = Faraday.get(url) do |req|
        req.options.timeout = 10
        req.headers['User-Agent'] = ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
      end
      
      end_time = Time.current
      response_time_ms = ((end_time - start_time) * 1000).round
      
      if response.success?
        update_columns(
          status: 'online',
          status_checked_at: Time.current,
          response_time: response_time_ms,
          last_error: nil
        )
        'online'
      elsif [301, 302, 303, 307, 308].include?(response.status)
        # Redirects are considered normal/online
        update_columns(
          status: 'online',
          status_checked_at: Time.current,
          response_time: response_time_ms,
          last_error: nil
        )
        'online'
      else
        update_columns(
          status: 'http_error',
          status_checked_at: Time.current,
          response_time: response_time_ms,
          last_error: "HTTP #{response.status}: #{response.reason_phrase}"
        )
        'http_error'
      end
    rescue Faraday::ConnectionFailed => e
      update_columns(
        status: 'connection_failed',
        status_checked_at: Time.current,
        response_time: nil,
        last_error: e.message
      )
      'connection_failed'
    rescue Faraday::TimeoutError => e
      update_columns(
        status: 'timeout',
        status_checked_at: Time.current,
        response_time: nil,
        last_error: e.message
      )
      'timeout'
    rescue Faraday::SSLError => e
      update_columns(
        status: 'ssl_error',
        status_checked_at: Time.current,
        response_time: nil,
        last_error: e.message
      )
      'ssl_error'
    rescue => e
      update_columns(
        status: 'error',
        status_checked_at: Time.current,
        response_time: nil,
        last_error: "#{e.class.name}: #{e.message}"
      )
      'error'
    end
  end

  def status_stale?
    status_checked_at.nil? || status_checked_at < 1.hour.ago
  end

  def online?
    status == 'online'
  end

  def offline?
    !online? && status.present?
  end

  def status_color
    case status
    when 'online'
      'success'
    when 'timeout', 'connection_failed'
      'warning'
    when 'http_error', 'ssl_error', 'error'
      'danger'
    else
      'secondary'
    end
  end

  def status_description
    case status
    when 'online'
      "Online (#{response_time}ms)"
    when 'timeout'
      'Request timeout'
    when 'connection_failed'
      'Connection failed'
    when 'http_error'
      'HTTP error'
    when 'ssl_error'
      'SSL certificate error'
    when 'error'
      'Unknown error'
    else
      'Status unknown'
    end
  end

  def robots_txt_url
    "#{url.chomp('/')}/robots.txt"
  end

  def fetch_robots_txt
    return if url.blank?
    
    begin
      response = Faraday.get(robots_txt_url) do |req|
        req.options.timeout = 10
      end
      
      if response.success?
        update_columns(
          robots_txt_content: response.body,
          robots_txt_updated_at: Time.current,
          robots_txt_status: 'success'
        )
        true
      elsif response.status == 404
        update_columns(
          robots_txt_content: nil,
          robots_txt_updated_at: Time.current,
          robots_txt_status: 'not_found'
        )
        true
      else
        update_columns(
          robots_txt_content: nil,
          robots_txt_updated_at: Time.current,
          robots_txt_status: "error_#{response.status}"
        )
        false
      end
    rescue => e
      update_columns(
        robots_txt_content: nil,
        robots_txt_updated_at: Time.current,
        robots_txt_status: "error_#{e.class.name.downcase}"
      )
      false
    end
  end

  def robots_txt_stale?
    robots_txt_updated_at.nil? || robots_txt_updated_at < 1.day.ago
  end

  def can_crawl?(path, user_agent = nil)
    user_agent ||= ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
    RobotsTxtParser.new(robots_txt_content).can_crawl?(path, user_agent)
  end

  def can_crawl_api?(user_agent = nil)
    user_agent ||= ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
    return true if robots_txt_content.blank?
    
    parser = RobotsTxtParser.new(robots_txt_content)
    
    return false unless parser.can_crawl?('/', user_agent)
    
    api_paths = ['/api', '/api/']
    api_paths.all? { |path| parser.can_crawl?(path, user_agent) }
  end

  def http_client(path = '/', user_agent = nil)
    user_agent ||= ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
    
    if status_stale?
      check_status
    end
    
    if offline?
      return nil
    end
    
    if robots_txt_stale?
      fetch_robots_txt
    end
    
    unless can_crawl?(path, user_agent)
      return nil
    end
    
    Faraday.new(url: url) do |faraday|
      faraday.use Faraday::FollowRedirects::Middleware
      faraday.headers['User-Agent'] = user_agent
      faraday.adapter Faraday.default_adapter
    end
  end

  def api_client(user_agent = nil)
    user_agent ||= ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
    
    if status_stale?
      check_status
    end
    
    if offline?
      return nil
    end
    
    if robots_txt_stale?
      fetch_robots_txt
    end
    
    unless can_crawl_api?(user_agent)
      return nil
    end
    
    Faraday.new(url: url) do |faraday|
      faraday.use Faraday::FollowRedirects::Middleware
      faraday.headers['User-Agent'] = user_agent
      faraday.adapter Faraday.default_adapter
    end
  end
end
