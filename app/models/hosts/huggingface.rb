module Hosts
  class Huggingface < Base
    IGNORABLE_EXCEPTIONS = [Faraday::Error, JSON::ParserError]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'huggingface'
    end

    def url(repository)
      "#{@host.url}/#{repository.full_name}"
    end

    def download_url(repository, branch = nil, kind = 'branch')
      revision = branch.presence || repository.default_branch.presence || 'main'
      "#{@host.url}/#{repository.full_name}/archive/#{CGI.escape(revision)}.zip"
    end

    def blob_url(repository, sha = nil)
      revision = sha.presence || repository.default_branch.presence || 'main'
      "#{@host.url}/#{repository.full_name}/tree/#{CGI.escape(revision)}/"
    end

    def recently_changed_repo_names(since = 1.hour)
      cutoff = Time.now - since
      models.sort_by { |model| parse_time(model['lastModified']) || Time.at(0) }.reverse.take_while do |model|
        parse_time(model['lastModified'])&.>=(cutoff)
      end.map { |model| model['id'] || model['modelId'] }.compact
    rescue Faraday::Error
      []
    end

    def crawl_repositories_async
      models.each { |model| @host.sync_repository_async(model['id'] || model['modelId']) }
    rescue Faraday::Error
      nil
    end

    def crawl_repositories
      models.each { |model| @host.sync_repository(model['id'] || model['modelId']) }
    rescue Faraday::Error
      nil
    end

    def load_owner_repos_names(owner)
      models(author: owner.login).map { |model| model['id'] || model['modelId'] }.compact
    rescue Faraday::Error
      []
    end

    def fetch_repository(id_or_name)
      data = model(id_or_name)
      return nil if data.blank? || data['private']
      map_repository_data(data)
    rescue Faraday::Error
      nil
    end

    def map_repository_data(data)
      full_name = data['id'].presence || data['modelId']
      updated_at = parse_time(data['lastModified'])
      license = Array(data['tags']).find { |tag| tag.start_with?('license:') }&.delete_prefix('license:')
      {
        uuid: data['_id'].presence || full_name,
        full_name: full_name,
        owner: data['author'].presence || full_name.to_s.split('/').first,
        description: data['cardData'].is_a?(Hash) ? data['cardData']['description'] : nil,
        homepage: data['model-index'].present? ? data['model-index'].to_s : nil,
        fork: false,
        private: data['private'],
        archived: data['disabled'],
        scm: 'git',
        default_branch: 'main',
        stargazers_count: data['likes'],
        subscribers_count: data['downloads'],
        topics: Array(data['tags']),
        license: license,
        language: data['library_name'],
        pushed_at: updated_at,
        updated_at: updated_at,
        created_at: parse_time(data['createdAt']) || updated_at || Time.at(0),
        has_issues: false,
        has_wiki: false,
        pull_requests_enabled: false,
        mirror_url: "#{@host.url}/#{full_name}",
        metadata: {
          huggingface: {
            pipeline_tag: data['pipeline_tag'],
            library_name: data['library_name'],
            gated: data['gated'],
            sha: data['sha']
          }
        }
      }
    end

    def model(id_or_name)
      response = api_client.get("/api/models/#{CGI.escape(id_or_name.to_s)}")
      return {} unless response.success? && response.body.respond_to?(:to_h)
      response.body.to_h
    end

    def models(author: nil, limit: 100)
      params = { limit: limit, sort: 'lastModified', direction: -1 }
      params[:author] = author if author.present?
      response = api_client.get('/api/models', params)
      return [] unless response.success? && response.body.is_a?(Array)
      response.body
    end

    def api_client
      Faraday.new(@host.url, request: { timeout: 30 }) do |conn|
        conn.response :json
      end
    end

    def parse_time(value)
      return if value.blank?
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
