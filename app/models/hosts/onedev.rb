module Hosts
  class Onedev < Base
    IGNORABLE_EXCEPTIONS = [Faraday::ResourceNotFound, Faraday::UnauthorizedError, Faraday::ForbiddenError]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'onedev'
    end

    def url(repository)
      "#{@host.url}/#{repository.full_name}"
    end

    def blob_url(repository, sha = nil)
      sha ||= repository.default_branch.presence || 'main'
      "#{url(repository)}/~files/#{CGI.escape(sha)}/"
    end

    def raw_url(repository, sha = nil)
      sha ||= repository.default_branch.presence || 'main'
      "#{url(repository)}/~raw/#{CGI.escape(sha)}/"
    end

    def tag_url(repository, tag_name)
      "#{url(repository)}/~files/#{CGI.escape(tag_name)}"
    end

    def recently_changed_repo_names(since = 1.hour)
      projects = query_projects('order by "Update Date" desc')
      cutoff = Time.now - since
      projects.take_while { |project| parse_time(project['updateDate'])&.> cutoff }.map { |project| project['path'] }.compact
    rescue *IGNORABLE_EXCEPTIONS
      []
    end

    def load_owner_repos_names(owner)
      query_projects(%("Path" is "#{owner.login}/**")).map { |project| project['path'] }.compact
    rescue *IGNORABLE_EXCEPTIONS
      []
    end

    def crawl_repositories
      offset = (REDIS.get("onedev_last_offset:#{@host.id}") || 0).to_i
      repos = query_projects(nil, offset)
      return unless repos.present?
      repos.each { |repo| @host.sync_repository(repo['path']) if repo['path'].present? }
      REDIS.set("onedev_last_offset:#{@host.id}", offset + repos.length)
    rescue Faraday::Error
      nil
    end

    def crawl_repositories_async
      offset = (REDIS.get("onedev_last_offset:#{@host.id}") || 0).to_i
      repos = query_projects(nil, offset)
      return unless repos.present?
      repos.each { |repo| @host.sync_repository_async(repo['path']) if repo['path'].present? }
      REDIS.set("onedev_last_offset:#{@host.id}", offset + repos.length)
    rescue Faraday::Error
      nil
    end

    def fetch_repository(id_or_name)
      project_id = id_or_name.to_s.match?(/\A\d+\z/) ? id_or_name : project_id_for_path(id_or_name)
      return nil unless project_id

      resp = api_client.get("~api/projects/#{project_id}")
      return nil unless resp.success? && resp.body.present?

      data = resp.body
      data['defaultBranch'] ||= fetch_default_branch(project_id)
      map_repository_data(data)
    rescue Faraday::Error
      nil
    end

    def map_repository_data(data)
      full_name = data['path'].presence || data['name']
      owner = full_name.to_s.split('/')[0...-1].join('/')
      {
        uuid: data['id'],
        full_name: full_name,
        owner: owner.presence,
        description: data['description'],
        fork: data['forkedFromId'].present?,
        created_at: data['createDate'],
        updated_at: data['updateDate'],
        default_branch: data['defaultBranch'],
        has_issues: data['issueManagement'],
        pull_requests_enabled: data['codeManagement'],
        private: false,
        scm: 'git',
        source_name: fetch_source_path(data['forkedFromId']),
        topics: [],
      }
    end

    def fetch_owner(login)
      {
        uuid: login,
        login: login,
        name: login,
        kind: 'organization'
      }
    end

    def api_client
      Faraday.new(@host.url, request: { timeout: 30 }) do |conn|
        token = REDIS.get("onedev_token:#{@host.id}")
        conn.request :authorization, :bearer, token if token.present?
        conn.response :json
      end
    end

    private

    def query_projects(query = nil, offset = 0, count = 100)
      params = { offset: offset, count: count }
      params[:query] = query if query.present?
      resp = api_client.get('~api/projects', params)
      return [] unless resp.success?
      resp.body.is_a?(Array) ? resp.body : []
    end

    def project_id_for_path(path)
      resp = api_client.get("~api/projects/ids/#{path}")
      resp.success? ? resp.body : nil
    end

    def fetch_default_branch(project_id)
      resp = api_client.get("~api/repositories/#{project_id}/default-branch")
      resp.success? ? resp.body : nil
    rescue Faraday::Error
      nil
    end

    def fetch_source_path(project_id)
      return nil if project_id.blank?
      resp = api_client.get("~api/projects/#{project_id}")
      resp.success? ? resp.body['path'] : nil
    rescue Faraday::Error
      nil
    end

    def parse_time(value)
      Time.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
