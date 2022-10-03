json.extract! @usage, :ecosystem, :name, :dependents_count, :requirements, :kind, :direct
json.dependent_repositories do
  json.array! @repositories, partial: 'api/v1/repositories/repository', as: :repository
end