class Owner < ApplicationRecord
  belongs_to :host

  validates :login, presence: true

  scope :created_after, ->(date) { where('created_at > ?', date) }
  scope :updated_after, ->(date) { where('updated_at > ?', date) }
  
  def self.sync_least_recently_synced
    Owner.order('last_synced_at asc nulls first').limit(1000).each(&:sync_async)
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

  def funding_links
    metadata['has_sponsors_listing'] ? ["https://github.com/sponsors/#{login}"] : []
  end

  def html_url
    "#{host.url}/#{login}"
  end

  def update_repositories_count
    update_column(:repositories_count, repositories.count)
  end

  def sync_repositories
    host.sync_owner_repositories_async(self)
  end
end
