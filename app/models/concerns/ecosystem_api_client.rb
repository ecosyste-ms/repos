module EcosystemApiClient
  extend ActiveSupport::Concern

  class_methods do
    def ecosystem_connection(base_url)
      Faraday.new(url: base_url) do |faraday|
        faraday.use Faraday::FollowRedirects::Middleware
        faraday.headers['User-Agent'] = ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
        faraday.headers['X-API-Key'] = ENV['ECOSYSTEMS_API_KEY'] if ENV['ECOSYSTEMS_API_KEY']
        faraday.adapter Faraday.default_adapter
      end
    end
  end

  private

  def ecosystem_connection(base_url)
    self.class.ecosystem_connection(base_url)
  end
end