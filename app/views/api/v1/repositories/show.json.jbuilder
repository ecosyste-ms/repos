json.partial! 'api/v1/repositories/repository', repository: @repository
json.funding_links @repository.funding_links
json.host @repository.host, partial: 'api/v1/hosts/host', as: :host