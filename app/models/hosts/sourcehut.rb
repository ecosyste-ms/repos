module Hosts
  class Sourcehut < Base
    IGNORABLE_EXCEPTIONS = [
      Faraday::ResourceNotFound
    ]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'sr-ht'
    end

    def url(repository)
      "#{git_host_url}/#{sourcehut_full_name(repository.full_name)}"
    end

    def html_url(repository)
      url(repository)
    end

    def blob_url(repository, sha = nil)
      sha ||= repository.default_branch.presence || 'master'
      "#{url(repository)}/tree/#{CGI.escape(sha)}/"
    end

    def raw_url(repository, sha = nil)
      sha ||= repository.default_branch.presence || 'master'
      "#{url(repository)}/blob/#{CGI.escape(sha)}/"
    end

    def download_url(repository, branch = nil, kind = 'branch')
      ref = branch || repository.default_branch.presence || 'master'
      "#{url(repository)}/archive/#{CGI.escape(ref)}.tar.gz"
    end

    def fetch_repository(id_or_name)
      full_name = sourcehut_full_name(id_or_name)
      resp = Faraday.get("#{git_host_url}/#{full_name}")
      return nil unless resp.success? && resp.body.present?

      map_repository_data(full_name, resp.body)
    rescue *IGNORABLE_EXCEPTIONS
      nil
    rescue Faraday::Error
      nil
    end

    def map_repository_data(full_name, html)
      owner, name = full_name.split('/', 2)
      title = html[/<title>\s*#{Regexp.escape(full_name)}\s*-\s*(.*?)\s*-\s*sourcehut git\s*<\/title>/m, 1]
      description = html[/<div class="header-extension">.*?<div class="col-md-6">\s*(.*?)\s*<\/div>/m, 1]
      default_branch = html[/<meta name="vcs:default-branch" content="([^"]+)"/, 1]
      scm = html[/<meta name="vcs" content="([^"]+)"/, 1]
      pushed_at = html[/<span title="([^"]+ UTC)">/, 1]

      {
        uuid: full_name,
        full_name: full_name,
        owner: owner.delete_prefix('~'),
        description: cleanup_html_text(description.presence || title),
        default_branch: default_branch.presence || 'master',
        scm: scm.presence || 'git',
        private: false,
        fork: false,
        archived: false,
        has_issues: false,
        pull_requests_enabled: false,
        created_at: parse_time(pushed_at) || Time.now,
        updated_at: parse_time(pushed_at) || Time.now,
        pushed_at: parse_time(pushed_at),
      }
    end

    def fetch_owner(login)
      sourcehut_login = login.to_s.delete_prefix('~')
      {
        uuid: sourcehut_login,
        login: sourcehut_login,
        name: sourcehut_login,
        kind: 'user'
      }
    end

    private

    def git_host_url
      @host.url.sub(%r{https://sr\.ht/?\z}, 'https://git.sr.ht').delete_suffix('/')
    end

    def sourcehut_full_name(id_or_name)
      parts = id_or_name.to_s.delete_prefix('/').split('/', 2)
      owner = parts.first.to_s
      repo = parts.second.to_s
      owner = "~#{owner}" unless owner.start_with?('~')
      [owner, repo].reject(&:blank?).join('/')
    end

    def cleanup_html_text(text)
      CGI.unescapeHTML(text.to_s.gsub(/<[^>]+>/, ' ').squish)
    end

    def parse_time(value)
      Time.parse(value) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
