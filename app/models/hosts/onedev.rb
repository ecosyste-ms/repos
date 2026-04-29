module Hosts
  class Onedev < Base
    IGNORABLE_EXCEPTIONS = [
      Faraday::ResourceNotFound
    ]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'onedev'
    end

    def url(repository)
      "#{@host.url}/#{repository.full_name}"
    end

    def download_url(repository, branch = nil, kind = 'branch')
      sha = branch || repository.default_branch.presence || 'main'
      "#{url(repository)}/~archive/#{CGI.escape(sha)}.zip"
    end

    def raw_url(repository, sha = nil)
      sha ||= repository.default_branch.presence || 'main'
      "#{url(repository)}/~raw/#{CGI.escape(sha)}/"
    end

    def load_repo_names(page, _order = nil)
      offset = (page - 1) * 100
      resp = api_client.get("~api/projects?offset=#{offset}&count=100")
      return [] unless resp.success?

      resp.body.select { |project| project['codeManagement'] }.map { |project| project['path'] }
    end

    def crawl_repositories
      page = (REDIS.get("onedev_last_page:#{@host.id}") || 0).to_i + 1
      names = load_repo_names(page)
      return if names.blank?

      names.each { |name| @host.sync_repository(name) }
      REDIS.set("onedev_last_page:#{@host.id}", page)
    rescue Faraday::Error
      nil
    end

    def crawl_repositories_async
      page = (REDIS.get("onedev_last_page:#{@host.id}") || 0).to_i + 1
      names = load_repo_names(page)
      return if names.blank?

      names.each { |name| @host.sync_repository_async(name) }
      REDIS.set("onedev_last_page:#{@host.id}", page)
    rescue Faraday::Error
      nil
    end

    def fetch_repository(id_or_name)
      project = if id_or_name.to_s.match?(/\A\d+\Z/)
        fetch_project(id_or_name)
      else
        find_project_by_path(id_or_name)
      end
      return nil unless project.present? && project['codeManagement']

      map_repository_data(project)
    rescue Faraday::Error
      nil
    end

    def find_project_by_path(path)
      page = 1

      loop do
        projects = api_projects(page)
        return nil if projects.blank?

        project = projects.find { |candidate| candidate['path'].casecmp?(path.to_s) }
        return project if project.present?

        page += 1
      end
    end

    def fetch_project(id)
      resp = api_client.get("~api/projects/#{id}")
      return nil unless resp.success?

      resp.body
    end

    def api_projects(page)
      offset = (page - 1) * 100
      resp = api_client.get("~api/projects?offset=#{offset}&count=100")
      return [] unless resp.success?

      resp.body
    end

    def map_repository_data(project)
      {
        uuid: project['id'],
        full_name: project['path']&.strip,
        owner: project['path'].to_s.split('/').first,
        description: project['description'],
        fork: project['forkedFromId'].present?,
        created_at: project['createDate'],
        updated_at: project['updateDate'] || project['createDate'],
        default_branch: 'main',
        has_issues: project['issueManagement'],
        private: false,
        scm: 'git',
        pull_requests_enabled: true,
        archived: false,
        source_name: nil,
      }
    end

    def api_client
      Faraday.new(@host.url, request: { timeout: 30 }) do |conn|
        token = REDIS.get("onedev_token:#{@host.id}")
        conn.request :authorization, :bearer, token if token.present?
        conn.response :json
      end
    end
  end
end
