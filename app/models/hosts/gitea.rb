module Hosts
  class Gitea < Base
    IGNORABLE_EXCEPTIONS = [
      Faraday::ResourceNotFound
    ]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'go-gitea'
    end

    def avatar_url(repository, _size = 60)
      repository.logo_url
    end

    def download_url(repository, branch = nil)
      sha = branch || repository.default_branch
      "#{url(repository)}/archive/#{CGI.escape(sha)}.zip"
    end

    def recently_changed_repo_names(since = 1.hour)
      target_time = Time.now - since
      names = []
      page = 1

      repos = load_repo_names(page, 'updated')
      return [] unless repos.any?
      oldest = repos.last["updated_at"]
      names += repos.map{|repo| repo["full_name"] }

      while oldest > target_time
        page += 1
        repos = load_repo_names(page, 'updated')
        break unless repos.any?
        oldest = repos.last["updated_at"]
        names += repos.map{|repo| repo["full_name"] }
      end

      return names
    end

    def load_repo_names(page, order)
      data = api_client.get("/api/v1/repos/search?sort=#{order}&page=#{page}&limit=100").body
      data['data']
    end

    def crawl_repositories
      page = (REDIS.get("gitea_last_page:#{@host.id}") || 0).to_i
      page += 1
      data = api_client.get("/api/v1/repos/search?sort=id&page=#{page}&limit=100").body
      repos = data['data']
      if repos.any?
        repos.each{|repo| @host.sync_repository_async(repo["full_name"])  }
        REDIS.set("gitea_last_page:#{@host.id}", page)
      end
    end

    def fetch_repository(id_or_name)
      id_or_name = id_or_name.to_i if id_or_name.match(/\A\d+\Z/)

      if id_or_name.is_a? Integer
        url = "/api/v1/repositories/#{id_or_name}"
      else
        url = "/api/v1/repos/#{id_or_name}"
      end
      data = api_client.get(url).body
      map_repository_data(data)
    end

    def map_repository_data(data)
      {
        uuid: data['id'],
        full_name: data['full_name'],
        owner: data['owner']['login'],
        main_language: data['language'],
        language: data['language'],
        archived: data['archived'],
        fork: data['fork'],
        description: data['description'],
        size: data['size'],
        stargazers_count: data['stars_count'],
        open_issues_count: data['open_issues_count'],
        forks_count: data['forks_count'],
        default_branch: data['default_branch'],
        homepage: data['website'],
        has_issues: data['has_issues'],
        has_wiki: data['has_wiki'],
        mirror_url: data['mirror'],
        source_name: data.fetch('parent',{}).try(:fetch, 'full_name', nil),
        private: data['private'],
        scm: 'git',
        pull_requests_enabled: data['has_pull_requests'],
        logo_url: data['avatar_url'].presence || data['owner']['avatar_url'],
        created_at: data['created_at'],
        updated_at: data['updated_at']
      }
    end

    def api_client
      Faraday.new(@host.url) do |conn|
        conn.request :authorization, :bearer, REDIS.get("gitea_token:#{@host.id}")
        conn.response :json 
      end
    end
  end
end