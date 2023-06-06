json.extract! usage, :ecosystem, :name, :dependents_count
json.package_usage_url api_v1_usage_url(usage.ecosystem, usage.name)
json.dependencies_url api_v1_usage_dependencies_url(usage.ecosystem, usage.name)