module Hosts
  class Gerrit < Base
    IGNORABLE_EXCEPTIONS = [Faraday::ResourceNotFound, Faraday::ConnectionFailed, Faraday::TimeoutError]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'git'
    end

    def url(repository)
      "#{@host.url.to_s.chomp('/')}/plugins/gitiles/#{CGI.escape(repository.full_name)}"
    end

    def html_url(repository)
      url(repository)
    end

    def raw_url(repository, sha = nil)
      sha ||= repository.default_branch.presence || 'HEAD'
      "#{url(repository)}/+/#{CGI.escape(sha)}/"
    end

    def blob_url(repository, sha = nil)
      raw_url(repository, sha)
    end

    def download_url(repository, branch = nil, kind = 'branch')
      ref = branch.presence || repository.default_branch.presence || 'HEAD'
      "#{url(repository)}/+archive/#{CGI.escape(ref)}.tar.gz"
    end

    def fetch_repository(id_or_name, _token = nil)
      name = id_or_name.to_s
      resp = api_client.get("/projects/#{CGI.escape(name)}")
      return nil unless resp.success?

      map_repository_data(gerrit_json(resp.body))
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def map_repository_data(data)
      {
        uuid: data['id'] || data['name'],
        full_name: data['name'] || data['id'],
        owner: data['parent'],
        description: data['description'],
        default_branch: data['branches']&.dig('HEAD') || 'master',
        fork: false,
        archived: data['state'] == 'READ_ONLY',
        private: false,
        scm: 'git',
        has_issues: false,
        has_wiki: false,
        pull_requests_enabled: false,
        topics: [],
        created_at: nil,
        updated_at: nil,
        pushed_at: nil,
        metadata: {
          state: data['state'],
          parent: data['parent'],
          web_links: data['web_links']
        }.compact
      }
    end

    def load_repo_names(limit = 100, prefix = nil)
      params = { n: limit }
      params[:p] = prefix if prefix.present?
      resp = api_client.get('/projects/', params)
      return [] unless resp.success?

      gerrit_json(resp.body).keys
    rescue *IGNORABLE_EXCEPTIONS
      []
    end

    def crawl_repositories
      load_repo_names.each { |name| @host.sync_repository(name) }
    end

    def crawl_repositories_async
      load_repo_names.each { |name| @host.sync_repository_async(name) }
    end

    def download_tags(repository)
      nil
    end

    def download_releases(repository)
      nil
    end

    def host_version
      resp = api_client.get('/config/server/version')
      return gerrit_json(resp.body) if resp.success?
    rescue
      nil
    end

    def api_client
      Faraday.new(@host.url, request: { timeout: 30 }) do |conn|
        conn.response :raise_error
      end
    end

    private

    def gerrit_json(body)
      JSON.parse(body.to_s.sub(/\A\)\]\}'\n?/, ''))
    end
  end
end
