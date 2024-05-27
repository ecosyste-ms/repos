json.array! @dependencies do |dependency|
  next if dependency.repository.nil?
  json.extract! dependency, :id, :package_name, :ecosystem, :requirements, :direct, :kind, :optional
  json.repository do
    json.partial! 'api/v1/repositories/repository', repository: dependency.repository
  end
  json.manifest do
    json.extract! dependency.manifest, :ecosystem, :filepath, :sha, :kind, :created_at, :updated_at
  end
end