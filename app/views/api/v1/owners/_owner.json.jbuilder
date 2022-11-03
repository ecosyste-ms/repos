json.extract! owner, :login, :name, :uuid, :kind, :description, :email, :website, :location, :twitter, :company, :avatar_url, :repositories_count, :last_synced_at, :metadata
json.owner_url api_v1_host_owner_url(owner.host, owner)
