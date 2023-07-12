class Host < ApplicationRecord
  validates_presence_of :name, :url, :kind
  validates_uniqueness_of :name, :url

  has_many :repositories
  has_many :owners

  def find_repository(full_name)
    repo = repositories.find_by('lower(full_name) = ?', full_name.downcase)
    repo = repositories.where('previous_names @> ?', "{#{full_name.downcase}}").to_a.first if repo.nil?
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

  def sync_repository(full_name)
    return if full_name.blank?
    puts "syncing #{full_name}"
    repo = repositories.find_by('lower(full_name) = ?', full_name.downcase)

    if repo
      repo.sync
    else
      repo_hash = host_instance.fetch_repository(full_name)
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
        repo.sync_extra_details_async if repo_changed && repo.persisted? && repo.files_changed?
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

  def crawl_repositories_async
    host_instance.crawl_repositories_async
  end

  def crawl_repositories
    host_instance.crawl_repositories
  end

  def download_tags(repository)
    host_instance.download_tags(repository)
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
  
    url = "https://timeline.ecosyste.ms/api/v1/events?per_page=1000&event_type=PullRequestEvent"
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
    return existing_owner if existing_owner && existing_owner.last_synced_at && existing_owner.last_synced_at > 1.day.ago
    owner_hash = host_instance.fetch_owner(login)
    if owner_hash.nil?
      owners.find_by('lower(login) = ?', login).try(:check_status)
      return nil 
    end
    
    owner = owners.find_by(uuid: owner_hash[:uuid])
    owner = owners.find_by('lower(login) = ?', owner_hash[:login].downcase) if owner.nil?
    if owner.nil?
      owner = owners.new(uuid: owner_hash[:id], login: owner_hash[:login])
    end
    owner.assign_attributes(owner_hash)
    owner.last_synced_at = Time.now
    owner.repositories_count = repositories.where(owner: owner.login).count
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
end
