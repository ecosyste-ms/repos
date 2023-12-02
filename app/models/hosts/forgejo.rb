module Hosts
  class Forgejo < Gitea
    
    def icon
      'forgejo'
    end
    
    def api_client
      Faraday.new(@host.url, request: {timeout: 30}) do |conn|
        conn.request :authorization, :bearer, REDIS.get("forgejo_token:#{@host.id}")
        conn.response :json        
      end
    end
  end
end