module Hosts
  class Cgit < Base
    IGNORABLE_EXCEPTIONS = [Faraday::ResourceNotFound, Faraday::ConnectionFailed, Faraday::TimeoutError]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'git'
    end

    def url(repository)
      "#{@host.url.to_s.chomp('/')}/#{repository.full_name}"
    end

    def html_url(repository)
      url(repository)
    end

    def raw_url(repository, sha = nil)
      sha ||= repository.default_branch.presence || 'master'
      "#{url(repository)}/plain/?h=#{CGI.escape(sha)}"
    end

    def blob_url(repository, sha = nil)
      raw_url(repository, sha)
    end

    def download_url(repository, branch = nil, kind = 'branch')
      ref = branch.presence || repository.default_branch.presence || 'master'
      "#{url(repository)}/snapshot/#{File.basename(repository.full_name)}-#{CGI.escape(ref)}.tar.gz"
    end

    def fetch_repository(id_or_name, _token = nil)
      full_name = id_or_name.to_s.sub(%r{\A/}, '').sub(%r{/\z}, '')
      resp = host_http_client("/#{full_name}/")
      return nil unless resp.success?

      map_repository_data(full_name, resp.body)
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def map_repository_data(full_name, html)
      doc = Nokogiri::HTML(html)
      title = doc.at('title')&.text.to_s.strip
      repo_name, description = title.split(' - ', 2)
      repo_name = File.basename(full_name) if repo_name.blank?
      default_branch = doc.at('link[rel="alternate"][type="application/atom+xml"]')&.[]('href').to_s[/[?&]h=([^&]+)/, 1]

      {
        uuid: full_name,
        full_name: full_name,
        owner: cgit_owner(full_name),
        description: description.presence,
        default_branch: default_branch.presence || 'master',
        fork: false,
        archived: false,
        private: false,
        scm: 'git',
        has_issues: false,
        has_wiki: false,
        pull_requests_enabled: false,
        topics: [],
        license: nil,
        homepage: nil,
        created_at: nil,
        updated_at: nil,
        pushed_at: nil,
        metadata: {
          cgit_name: repo_name,
          generator: doc.at('meta[name="generator"]')&.[]('content')
        }.compact
      }
    end

    def load_repo_names(_page = nil, _order = nil)
      resp = host_http_client('/')
      return [] unless resp.success?

      Nokogiri::HTML(resp.body).css('a').map { |a| a['href'].to_s }.filter_map do |href|
        next unless href.match?(%r{/[^/?]+/?\z})
        href.sub(%r{\A/}, '').sub(%r{/\z}, '')
      end.uniq
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

    private

    def cgit_owner(full_name)
      parts = full_name.split('/')
      return parts[-2] if parts.length > 1
    end
  end
end
