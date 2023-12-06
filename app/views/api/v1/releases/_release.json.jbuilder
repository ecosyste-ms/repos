json.extract! release, :name, :uuid, :tag_name, :target_commitish, :body, :draft, :prerelease, :published_at, :created_at, :author, :assets, :last_synced_at, :html_url
json.release_url api_v1_host_repository_release_url(release.repository.host, release.repository, release)
json.tag_url api_v1_host_repository_tag_url(release.repository.host, release.repository, release)