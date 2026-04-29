module Hosts
  class Sourceforge < Base
    IGNORABLE_EXCEPTIONS = [Faraday::Error, JSON::ParserError]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'sourceforge'
    end

    def url(repository)
      project, mount = split_full_name(repository.full_name)
      "https://sourceforge.net/p/#{CGI.escape(project)}/#{CGI.escape(mount)}/"
    end

    def download_url(repository, branch = nil, kind = 'branch')
      project, mount = split_full_name(repository.full_name)
      ref = branch.presence || repository.default_branch.presence || 'master'
      "https://sourceforge.net/p/#{CGI.escape(project)}/#{CGI.escape(mount)}/ci/#{CGI.escape(ref)}/tree/"
    end

    def blob_url(repository, sha = nil)
      project, mount = split_full_name(repository.full_name)
      ref = sha.presence || repository.default_branch.presence || 'master'
      "https://sourceforge.net/p/#{CGI.escape(project)}/#{CGI.escape(mount)}/ci/#{CGI.escape(ref)}/tree/"
    end

    def fetch_repository(id_or_name)
      project, mount = split_full_name(id_or_name)
      project_data = project(project)
      return nil if project_data.blank? || project_data['private']
      tool = code_tools(project_data).find { |code_tool| code_tool['mount_point'] == mount }
      return nil if tool.blank?
      map_repository_data(project_data, tool)
    rescue Faraday::Error
      nil
    end

    def load_owner_repos_names(owner)
      project(owner.login)['tools'].to_a.select { |tool| code_tool?(tool) }.map do |tool|
        "#{owner.login}/#{tool['mount_point']}"
      end
    rescue Faraday::Error
      []
    end

    def map_repository_data(project_data, tool)
      created_at = parse_date(project_data['creation_date'])
      {
        uuid: "#{project_data['shortname']}/#{tool['mount_point']}",
        full_name: "#{project_data['shortname']}/#{tool['mount_point']}",
        owner: project_data['shortname'],
        description: project_data['short_description'].presence || project_data['summary'],
        homepage: project_data['external_homepage'].presence || project_data['url'],
        fork: false,
        private: project_data['private'],
        archived: project_data['status'] != 'active',
        scm: tool['name'],
        default_branch: 'master',
        has_issues: has_issue_tool?(project_data),
        has_wiki: has_wiki_tool?(project_data),
        pull_requests_enabled: false,
        mirror_url: tool['clone_url_https_anon'].presence || tool['clone_url_ro'],
        logo_url: project_data['icon_url'],
        topics: category_topics(project_data),
        created_at: created_at,
        updated_at: created_at,
        metadata: {
          sourceforge: {
            project_name: project_data['name'],
            mount_label: tool['mount_label'],
            api_url: tool['api_url']
          }
        }
      }
    end

    def project(shortname)
      response = api_client.get("/rest/p/#{CGI.escape(shortname)}")
      return {} unless response.success? && response.body.respond_to?(:to_h)
      response.body.to_h
    end

    def api_client
      Faraday.new('https://sourceforge.net', request: { timeout: 30 }) do |conn|
        conn.response :json
      end
    end

    def split_full_name(full_name)
      project, mount = full_name.to_s.split('/', 2)
      [project, mount.presence || 'code']
    end

    def code_tools(project_data)
      project_data['tools'].to_a.select { |tool| code_tool?(tool) }
    end

    def code_tool?(tool)
      %w[git svn hg].include?(tool['name']) || tool['clone_url_https_anon'].present? || tool['clone_url_ro'].present?
    end

    def has_issue_tool?(project_data)
      project_data['tools'].to_a.any? { |tool| %w[tickets bugs support feature-requests].include?(tool['name']) || tool['mount_point'].to_s.match?(/ticket|bug|support|feature/) }
    end

    def has_wiki_tool?(project_data)
      project_data['tools'].to_a.any? { |tool| tool['name'] == 'wiki' || tool['mount_point'] == 'wiki' }
    end

    def category_topics(project_data)
      project_data['categories'].to_h.values.flatten.filter_map { |category| category['shortname'] }.uniq
    end

    def parse_date(value)
      return if value.blank?
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
