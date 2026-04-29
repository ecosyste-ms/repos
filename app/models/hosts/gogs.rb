module Hosts
  class Gogs < Gitea
    def icon
      'gogs'
    end

    def api_client
      Faraday.new(@host.url, request: {timeout: 30}) do |conn|
        conn.request :authorization, :token, REDIS.get("gogs_token:#{@host.id}")
        conn.response :json
      end
    end
  end
end
