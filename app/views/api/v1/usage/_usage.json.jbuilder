json.extract! usage, :ecosystem, :name, :dependents_count, :requirements, :kind, :direct
json.package_usage_url api_v1_usage_url(usage.ecosystem, usage.name)