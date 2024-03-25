json.extract! owner, :login, :name, :uuid, :kind, :description, :email, :website, :location, :twitter, :company, :icon_url, :repositories_count, :last_synced_at, :metadata, :html_url, :funding_links, :total_stars, :followers, :following, :created_at, :updated_at
json.owner_url api_v1_host_owner_url(owner.host, owner)
json.repositories_url repositories_api_v1_host_owner_url(owner.host, owner)