json.extract! tag, :name, :sha, :kind, :published_at, :download_url, :html_url, :dependencies_parsed_at, :dependency_job_id, :purl
json.tag_url api_v1_host_repository_tag_url(tag.repository.host, tag.repository, tag)
json.manifests_url api_v1_host_repository_tag_manifests_url(tag.repository.host, tag.repository, tag)