module Hosts
  class Gogs < Gitea
    def icon
      'gogs'
    end

    def fetch_topics(_full_name)
      []
    end

    def api_client
      Faraday.new(@host.url, request: { timeout: 30 }) do |conn|
        conn.request :authorization, :bearer, REDIS.get("gogs_token:#{@host.id}")
        conn.response :json
      end
    end
  end
end
