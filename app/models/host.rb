class Host < ApplicationRecord
  validates_presence_of :name, :url, :kind
  validates_uniqueness_of :name, :url

  has_many :repositories

  def update_repository_counts
    update_column(:repositories_count, repositories.count)
  end

  def to_s
    name
  end

  def to_param
    name
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

        repo.assign_attributes(repo_hash)
        repo.last_synced_at = Time.now
        repo.save
        # TODO sync extra things if stuff changed
        repo
      end
    end
  rescue *Array(host_class.api_missing_error_class)
    nil
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def sync_recently_changed_repos(since = 10.minutes)
    host_instance.recently_changed_repo_names(since).each do |full_name|
      sync_repository(full_name)
    end
  end

  def sync_recently_changed_repos_async(since = 10.minutes)
    host_instance.recently_changed_repo_names(since).each do |full_name|
      sync_repository_async(full_name)
    end
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

  def download_url(repository, branch = nil)
    host_instance.download_url(repository, branch)
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
  
      events = Oj.load(resp.body)
    rescue Faraday::Error
      events = nil
    end
  
    return unless events.present?
  
    events.each do |e| 
      hash = e['payload']['pull_request']['base']['repo'].to_hash.with_indifferent_access
      
      repo_hash = host_instance.map_repository_data(hash)
  
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
    end
  
    if events.any?
      next_id = events.last['id']
      puts "next id: #{next_id}" 
      REDIS.set('last_timeline_id', next_id)
      import_github_repos_from_timeline(next_id)
    end
  end
end
