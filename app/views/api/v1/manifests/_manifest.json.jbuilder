json.extract! manifest, :ecosystem, :filepath, :sha, :kind, :created_at, :updated_at

json.dependencies manifest.dependencies, partial: 'api/v1/dependencies/dependency', as: :dependency