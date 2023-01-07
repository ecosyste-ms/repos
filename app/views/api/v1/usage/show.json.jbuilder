json.extract! @usage, :ecosystem, :name, :dependents_count, :requirements, :kind, :direct
json.dependencies_url api_v1_usage_dependencies_url(@usage.ecosystem, @usage.name)