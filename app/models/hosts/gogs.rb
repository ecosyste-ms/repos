module Hosts
  class Gogs < Gitea
    def icon
      'gogs'
    end

    def fetch_topics(_full_name)
      []
    end

    def topic_url(_topic)
      nil
    end

    def host_version
      resp = api_client.get('api/v1/version')
      return resp.body['version'] if resp.success? && resp.body.is_a?(Hash)
    rescue
      nil
    end
  end
end
