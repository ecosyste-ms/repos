class Host < ApplicationRecord
  validates_presence_of :name, :url, :kind
  validates_uniqueness_of :name, :url

  has_many :repositories

  def to_s
    name
  end

  def to_param
    name
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
        repo = repositories.find_by(uuid: repo_hash[:uuid])
        repo = repositories.new(uuid: repo_hash[:id], full_name: repo_hash[:full_name]) if repo.nil?
        repo.full_name = repo_hash[:full_name] if repo.full_name.downcase != repo_hash[:full_name].downcase

        repo.assign_attributes(repo_hash)
        repo.last_synced_at = Time.now
        repo.save
        # TODO sync extra things if stuff changed
        repo
      end
    end
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
end
