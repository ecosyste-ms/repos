json.extract! repository, :id, :uuid, :full_name, :owner, :description, :archived, :fork, :pushed_at, :size, :stargazers_count, :open_issues_count,
  :forks_count, :subscribers_count, :default_branch, :last_synced_at, :etag, :topics, :latest_commit_sha, :homepage, :language, :has_issues,
  :has_wiki, :has_pages, :mirror_url, :source_name, :license, :status, :scm, :pull_requests_enabled, :icon_url, :metadata, :created_at, :updated_at,
  :dependencies_parsed_at, :dependency_job_id, :html_url, :commit_stats, :previous_names, :tags_count, :template, :template_full_name

json.repository_url api_v1_host_repository_url(repository.host, repository)
json.tags_url api_v1_host_repository_tags_url(repository.host, repository)
json.releases_url api_v1_host_repository_releases_url(repository.host, repository)
json.manifests_url api_v1_host_repository_manifests_url(repository.host, repository)
json.owner_url api_v1_host_owner_url(repository.host, repository.owner)
json.download_url repository.download_url
json.package_usages repository._package_usages do |package_usage|
  json.extract! package_usage, :id, :name, :ecosystem, :key
end
