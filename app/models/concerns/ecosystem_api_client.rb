module EcosystemApiClient
  extend ActiveSupport::Concern

  class_methods do
    def ecosystem_connection(base_url)
      Faraday.new(url: base_url) do |faraday|
        faraday.use Faraday::FollowRedirects::Middleware
        faraday.headers['User-Agent'] = 'repos.ecosyste.ms'
        faraday.adapter Faraday.default_adapter
      end
    end
  end

  private

  def ecosystem_connection(base_url)
    self.class.ecosystem_connection(base_url)
  end
end