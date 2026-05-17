module Hosts
  class Gitblit < Base
    IGNORABLE_EXCEPTIONS = [Faraday::Error]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'git'
    end

    def url(repository)
      "#{@host.url}/summary/#{CGI.escape(repository.full_name)}"
    end

    def download_url(repository, branch = nil, kind = 'branch')
      ref = branch.presence || repository.default_branch.presence || 'master'
      "#{@host.url}/zip/#{CGI.escape(repository.full_name)}/#{kind}/#{CGI.escape(ref)}"
    end

    def blob_url(repository, sha = nil)
      ref = sha.presence || repository.default_branch.presence || 'master'
      "#{@host.url}/blob/#{CGI.escape(repository.full_name)}/#{CGI.escape(ref)}/"
    end

    def recently_changed_repo_names(since = 1.hour)
      target_time = Time.now - since
      repositories.values.select do |repo|
        parse_time(repo['lastChange'])&.>=(target_time)
      end.map { |repo| repo['name'] }.compact
    end

    def load_repo_names(_page = nil, _order = nil)
      repositories.keys
    end

    def crawl_repositories_async
      repositories.each_key { |name| @host.sync_repository_async(name) }
    rescue Faraday::Error
      nil
    end

    def crawl_repositories
      repositories.each_key { |name| @host.sync_repository(name) }
    rescue Faraday::Error
      nil
    end

    def fetch_repository(id_or_name)
      data = repositories[id_or_name.to_s]
      return nil if data.blank?
      map_repository_data(data)
    rescue Faraday::Error
      nil
    end

    def map_repository_data(data)
      full_name = data['name'].to_s.gsub(/\.git\z/, '')
      last_change = parse_time(data['lastChange'])
      {
        uuid: full_name,
        full_name: full_name,
        owner: Array(data['owners']).first.presence || full_name.split('/').first,
        description: data['description'],
        fork: false,
        mirror_url: data['origin'],
        scm: 'git',
        size: parse_size(data['size']),
        default_branch: normalize_branch(data['HEAD']),
        created_at: last_change || Time.at(0),
        updated_at: last_change,
        pushed_at: last_change,
        has_issues: data['acceptNewTickets'],
        pull_requests_enabled: data['acceptNewPatchsets'],
        archived: data['isFrozen'],
        private: restricted?(data)
      }
    end

    def repositories
      response = api_client.get('/rpc/', req: 'LIST_REPOSITORIES')
      return {} unless response.success? && response.body.respond_to?(:to_h)
      response.body.to_h
    end

    def api_client
      Faraday.new(@host.url, request: { timeout: 30 }) do |conn|
        conn.response :json
      end
    end

    def parse_time(value)
      return if value.blank?
      value.is_a?(Numeric) ? Time.at(value.to_f / 1000) : Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_size(value)
      return if value.blank?
      value.to_s[/\d+/]&.to_i
    end

    def normalize_branch(head)
      head.to_s.sub(%r{\Arefs/heads/}, '').presence
    end

    def restricted?(data)
      data['accessRestriction'].present? && data['accessRestriction'] != 'NONE'
    end
  end
end
