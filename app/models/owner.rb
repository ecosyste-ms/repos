class Owner < ApplicationRecord
  belongs_to :host
  
  def to_s
    name.presence || login
  end

  def repositories
    host.repositories.where(owner: login)
  end

  def sync
    host.sync_owner(login)
  end

  def sync_async(login)
    SyncOwnerWorker.perform_async(host_id, login)
  end

  def funding_links
    metadata['has_sponsors_listing'] ? ["https://github.com/sponsors/#{login}"] : []
  end

  def html_url
    "#{host.html_url}/#{login}"
  end

  def update_repositories_count
    update_column(:repositories_count, repositories.count)
  end
end
