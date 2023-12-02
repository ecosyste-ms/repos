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

    def tag_url(repository, tag_name)
      "#{url(repository)}/source/tag/#{tag_name}"
    end

    def download_url(repository, branch = nil, kind = 'branch')
      sha = branch || repository.default_branch
      "#{url(repository)}/archive/#{CGI.escape(sha)}.zip"
    end

    def blob_url(repository, sha = nil)
      sha ||= repository.default_branch
      "#{url(repository)}/raw/#{CGI.escape(sha)}/"
    end

    def recently_changed_repo_names(since = 1.hour)
      target_time = Time.now - since
      names = []
      page = 1

      repos = load_repo_names(page, 'updated')
      return [] unless repos.present?
      oldest = repos.last["updated_at"]
      names += repos.map{|repo| repo["full_name"] }

      while oldest > target_time
        page += 1
        repos = load_repo_names(page, 'updated')
        break unless repos.present?
        oldest = repos.last["updated_at"]
        names += repos.map{|repo| repo["full_name"] }
      end

      return names.uniq
    end

    def topic_url(topic)
      "#{@host.url}/explore/explore/repos?q=#{topic}&topic=1"
    end

    def fetch_topics(full_name)
      resp = api_client.get("/api/v1/repos/#{full_name}/topics")
      return [] unless resp.success?
      resp.body['topics']
    end

    def download_tags(repository)
      existing_tag_names = repository.tags.pluck(:name)

      resp = api_client.get("/api/v1/repos/#{repository.full_name}/tags")
      return nil unless resp.success?
      # TODO pagination
      remote_tags = resp.body

      remote_tags.each do |tag|
        next if existing_tag_names.include?(tag['name'])
        next if tag['commit'].blank?
        repository.tags.create!({
          name: tag['name'],
          kind: "tag",
          sha: tag['commit']['sha'],
          published_at: tag['commit']['created']
        })
      end
      repository.update_columns(tags_last_synced_at: Time.now, tags_count: repository.tags.count)
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def load_owner_repos_names(owner)
      resp = api_client.get("/api/v1/users/#{owner.login}/repos")
      # TODO pagination
      return [] unless resp.success?
      resp.body.map{|repo| repo["full_name"] }
    end

    def load_repo_names(page, order)
      resp = api_client.get("/api/v1/repos/search?sort=#{order}&page=#{page}&limit=100")
      return [] unless resp.success?
      resp.body['data']
    end

    def crawl_repositories_async
      page = (REDIS.get("gitea_last_page:#{@host.id}") || 0).to_i
      page += 1
      resp = api_client.get("/api/v1/repos/search?sort=id&page=#{page}&limit=100")
      return unless resp.success?
      repos = resp.body['data']
      if repos.present?
        repos.each{|repo| @host.sync_repository_async(repo["full_name"])  }
        REDIS.set("gitea_last_page:#{@host.id}", page)
      end
    end

    def crawl_repositories
      page = (REDIS.get("gitea_last_page:#{@host.id}") || 0).to_i
      page += 1
      resp = api_client.get("/api/v1/repos/search?sort=id&page=#{page}&limit=100")
      return unless resp.success?
      repos = resp.body['data']
      if repos.present?
        repos.each{|repo| @host.sync_repository(repo["full_name"])  }
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
      resp = api_client.get(url)
      return nil unless resp.success?
      map_repository_data(resp.body)
    end

    def map_repository_data(data)
      {
        uuid: data['id'],
        full_name: data['full_name'],
        owner: data['owner']['login'],
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
        topics: fetch_topics(data['full_name']),
        created_at: data['created_at'],
        updated_at: data['updated_at']
      }
    end

    def api_client
      Faraday.new(@host.url, request: {timeout: 30}) do |conn|
        conn.request :authorization, :bearer, REDIS.get("gitea_token:#{@host.id}")
        conn.response :json        
      end
    end

    def fetch_owner(login)
      url = "/api/v1/users/#{login}"
      resp = api_client.get(url)
      return nil unless resp.success?
      owner = resp.body

      resp = api_client.get("/api/v1/orgs/#{login}")
      is_org = resp.success?
      {
        uuid: owner['id'],
        login: owner['login'],
        name: owner['full_name'],
        email: owner['email'],
        location: owner['location'],
        website: owner['website'],
        description: owner['description'],
        avatar_url: owner['avatar_url'],
        kind: is_org ? 'organization' : 'user'
      }
    end

    def host_version
      url = "#{@host.url}/swagger.v1.json"
      resp = Faraday.get(url)
      json = JSON.parse(resp.body)
      json['info']['version']
    rescue
      nil
    end
  end
end