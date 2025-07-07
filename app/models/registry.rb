class Registry < ApplicationRecord
  extend EcosystemApiClient
  
  def self.sync_all
    conn = ecosystem_connection(PACKAGES_DOMAIN)
    
    response = conn.get('/api/v1/registries')
    return nil unless response.success?
    json = JSON.parse(response.body)

    json.each do |registry|
      Registry.find_or_create_by(name: registry['name']).tap do |r|
        r.url = registry['url']
        r.ecosystem = registry['ecosystem']
        r.default = registry['default']
        r.packages_count = registry['packages_count']
        r.github = registry['github']
        r.metadata = registry['metadata']
        r.created_at = registry['created_at']
        r.updated_at = registry['updated_at']
        r.save
      end
    end
  end

  def self.find_by_ecosystem(ecosystem)
    Registry.where(ecosystem: ecosystem, default: true).first || Registry.where(ecosystem: ecosystem).first
  end

  def self.ecosystems
    Registry.pluck('DISTINCT ecosystem')
  end
end
