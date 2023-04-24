json.extract! host, :name, :url, :kind, :repositories_count, :owners_count, :icon_url
json.host_url api_v1_host_url(host)
json.repositories_url api_v1_host_repositories_url(host)
json.repository_names_url repository_names_api_v1_host_url(host)
json.owners_url api_v1_host_owners_url(host)