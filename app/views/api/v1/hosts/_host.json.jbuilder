json.extract! host, :name, :url, :kind, :repositories_count, :owners_count, :icon_url, :version, :created_at, :updated_at

# Status monitoring fields
json.status host.status
json.status_checked_at host.status_checked_at
json.response_time host.response_time
json.last_error host.last_error

# Robots.txt fields
json.robots_txt_status host.robots_txt_status
json.robots_txt_updated_at host.robots_txt_updated_at
json.robots_txt_url host.robots_txt_url

# Additional helper methods
json.online host.online?
json.can_crawl_api host.can_crawl_api?

json.host_url api_v1_host_url(host)
json.repositories_url api_v1_host_repositories_url(host)
json.repository_names_url repository_names_api_v1_host_url(host)
json.owners_url api_v1_host_owners_url(host)