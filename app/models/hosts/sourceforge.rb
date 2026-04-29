module Hosts
  class Sourceforge < Base
    IGNORABLE_EXCEPTIONS = [
      Faraday::ResourceNotFound
    ]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'sourceforge'
    end

    def url(repository)
      "#{@host.url}/projects/#{repository.full_name}"
    end

    def html_url(repository)
      url(repository)
    end

    def issues_url(repository)
      "#{@host.url}/p/#{repository.full_name}/tickets/"
    end

    def source_url(repository)
      "#{@host.url}/p/#{repository.source_name}/" if repository.source_name.present?
    end

    def download_url(repository, branch = nil, kind = 'branch')
      "#{@host.url}/projects/#{repository.full_name}/files/latest/download"
    end

    def fetch_repository(full_name)
      return nil if full_name.blank?

      response = api_client.get("/rest/p/#{CGI.escape(full_name)}/")
      return nil unless response.success? && response.body.is_a?(Hash)

      project = response.body
      return nil if project.blank? || project['private']

      map_repository_data(project)
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def map_repository_data(project)
      {
        uuid: project['_id'],
        full_name: project['shortname'],
        owner: project['shortname'],
        description: project['short_description'].presence || project['summary'],
        homepage: project['external_homepage'].presence,
        fork: false,
        created_at: project['creation_date'],
        updated_at: project['last_updated'],
        pushed_at: project['last_updated'],
        has_issues: true,
        private: project['private'],
        scm: 'unknown',
        pull_requests_enabled: false,
        logo_url: project['icon_url'],
        topics: Array(project['labels']).compact,
        archived: false
      }
    end

    def recently_changed_repo_names(_since = 1.hour)
      []
    end

    def crawl_repositories_async
      # SourceForge does not expose a simple recent-projects endpoint suitable
      # for incremental crawling. Repositories are synced on demand instead.
      nil
    end

    def crawl_repositories
      nil
    end

    def download_tags(_repository)
      nil
    end

    def download_releases(_repository)
      nil
    end

    def api_client
      Faraday.new(@host.url, request: { timeout: 30 }) do |conn|
        conn.response :json
      end
    end
  end
end
