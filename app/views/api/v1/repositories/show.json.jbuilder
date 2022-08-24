json.partial! 'api/v1/repositories/repository', repository: @repository
json.host @repository.host, partial: 'api/v1/hosts/host', as: :host