module Hosts
  class Github < Base
    IGNORABLE_EXCEPTIONS = [
      Octokit::Unauthorized,
      Octokit::InvalidRepository,
      Octokit::RepositoryUnavailable,
      # Octokit::NotFound,
      Octokit::Conflict,
      Octokit::Forbidden,
      Octokit::InternalServerError,
      Octokit::BadGateway,
      Octokit::UnavailableForLegalReasons
    ]

    def self.api_missing_error_class
      Octokit::NotFound
    end

    def token_set_key
      "github_tokens"
    end

    def fetch_random_token
      REDIS.srandmember(token_set_key)
    end

    def add_tokens(tokens)
      REDIS.sadd(token_set_key, tokens)
    end

    def remove_token(token)
      REDIS.srem(token_set_key, token)
    end

    def check_tokens
      REDIS.smembers(token_set_key).each do |token|
        begin
          api_client(token).rate_limit!
        rescue Octokit::Unauthorized, Octokit::AccountSuspended
          remove_token(token)
        end
      end
    end

    def html_url(repository)
      "https://github.com/#{repository.full_name}"
    end

    def avatar_url(repository, size = 40)
      "https://github.com/#{repository.owner}.png?size=#{size}"
    end

    def watchers_url
      "#{url}/watchers"
    end

    def forks_url
      "#{url}/network"
    end

    def stargazers_url
      "#{url}/stargazers"
    end

    def contributors_url
      "#{url}/graphs/contributors"
    end

    def blob_url(repository, sha = nil)
      sha ||= repository.default_branch
      "#{url(repository)}/blob/#{sha}/"
    end

    def commits_url(author = nil)
      author_param = author.present? ? "?author=#{author}" : ''
      "#{url}/commits#{author_param}"
    end

    def fetch_repository(id_or_name, token = nil)
      id_or_name = id_or_name.to_i if id_or_name.match(/\A\d+\Z/)

      # if id_or_name.is_a?(String)
      #   hash = attempt_load_from_timeline(id_or_name)
      #   puts "loaded #{id_or_name} from timeline" if hash.present?
      # end

      # if hash.nil?
        hash = api_client(token).repo(id_or_name, accept: 'application/vnd.github.drax-preview+json,application/vnd.github.mercy-preview+json').to_hash.with_indifferent_access
      # end

      map_repository_data(hash)
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def map_repository_data(hash)
      hash[:scm] = 'git'
      hash[:uuid] = hash[:id]
      hash[:license] = hash[:license][:key] if hash[:license]
      hash[:owner] = hash[:owner][:login]
      hash[:main_language] = hash[:language]

      if hash[:fork] && hash[:parent]
        hash[:source_name] = hash[:parent][:full_name]
      end

      return hash.slice(*repository_columns)
    end

    def get_file_list(repository, token = nil)
      tree = api_client(token).tree(repository.full_name, repository.default_branch, recursive: true).tree
      tree.select{|item| item.type == 'blob' }.map{|file| file.path }
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def get_file_contents(repository, path, token = nil)
      file = api_client(token).contents(repository.full_name, path: path)
      {
        sha: file.sha,
        content: file.content.present? ? Base64.decode64(file.content) : file.content
      }
    rescue URI::InvalidURIError
      nil
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def download_tags(repository, token = nil)
      existing_tag_names = repository.tags.pluck(:name)
      tags = api_client(token).refs(repository.full_name, 'tags')
      Array(tags).each do |tag|
        next unless tag && tag.is_a?(Sawyer::Resource) && tag['ref']
        download_tag(repository, token, tag, existing_tag_names)
      end
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def download_tag(repository, token, tag, existing_tag_names)
      match = tag.ref.match(/refs\/tags\/(.*)/)
      return unless match
      name = match[1]
      return if existing_tag_names.include?(name)

      object = api_client(token).get(tag.object.url)

      tag_hash = {
        name: name,
        kind: tag.object.type,
        sha: tag.object.sha
      }

      case tag.object.type
      when 'commit'
        tag_hash[:published_at] = object.committer.date
      when 'tag'
        tag_hash[:published_at] = object.tagger.date
      end

      repository.tags.create(tag_hash)
    end

    def recently_changed_repo_names(since = 1.hour)
      names = []

      first_response = load_repo_names
      return if first_response.blank?
      most_recent = first_response["newest"]["created_at"]
      target_time = Time.parse(most_recent) - since
      next_id = first_response['oldest']['id']

      next_response = load_repo_names(next_id)
      names = (names + next_response['names']).uniq
      next_id = next_response['oldest']['id']

      while Time.parse(next_response['oldest']['created_at']) > target_time
        next_response = load_repo_names(next_id)
        names = (names + next_response['names']).uniq
        next_id = next_response['oldest']['id']
      end

      return names
    end

    def load_repo_names(id = nil)
      puts "loading repo names since #{id}"
      url = "https://timeline.ecosyste.ms/api/v1/events/repository_names"
      url = "#{url}?before=#{id}" if id.present?
      begin
        resp = Faraday.get(url) do |req|
          req.options.timeout = 5
        end

        Oj.load(resp.body)
      rescue Faraday::Error
        {}
      end
    end

    def events_for_repo(full_name, event_type: nil, per_page: 100)
      url = "https://timeline.ecosyste.ms/api/v1/events/#{full_name}?per_page=#{per_page}"
      url = "#{url}&event_type=#{event_type}" if event_type.present?

      begin
        resp = Faraday.get(url) do |req|
          req.options.timeout = 5
        end

        Oj.load(resp.body)
      rescue Faraday::Error
        {}
      end
    end

    def attempt_load_from_timeline(full_name)
      events = events_for_repo(full_name, event_type: 'PullRequestEvent', per_page: 1)
      return nil if events.blank?
      events.first['payload']['pull_request']['base']['repo'].to_hash.with_indifferent_access
    rescue
      nil
    end

    private

    def api_client(token = nil, options = {})
      token = fetch_random_token if token.nil?
      Octokit::Client.new({access_token: token, auto_paginate: true}.merge(options))
    end
  end
end
