module Hosts
  class Github < Base
    IGNORABLE_EXCEPTIONS = [
      Octokit::Unauthorized,
      Octokit::InvalidRepository,
      Octokit::RepositoryUnavailable,
      Octokit::NotFound,
      Octokit::Conflict,
      Octokit::Forbidden,
      Octokit::InternalServerError,
      Octokit::BadGateway,
      Octokit::ClientError,
      Octokit::UnavailableForLegalReasons
    ]

    def self.api_missing_error_class
      Octokit::NotFound
    end

    def avatar_url(size = 60)
      "https://github.com/#{repository.owner_name}.png?size=#{size}"
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

    def blob_url(sha = nil)
      sha ||= repository.default_branch
      "#{url}/blob/#{sha}/"
    end

    def commits_url(author = nil)
      author_param = author.present? ? "?author=#{author}" : ''
      "#{url}/commits#{author_param}"
    end

    def fetch_repository(id_or_name, token = nil)
      id_or_name = id_or_name.to_i if id_or_name.match(/\A\d+\Z/)
      hash = api_client(token).repo(id_or_name, accept: 'application/vnd.github.drax-preview+json,application/vnd.github.mercy-preview+json').to_hash.with_indifferent_access
      pp hash.keys
      hash[:scm] = 'git'
      hash[:uuid] = hash[:id]
      hash[:license] = hash[:license][:key] if hash[:license]

      if hash[:fork] && hash[:parent]
        hash[:source_name] = hash[:parent][:full_name]
      end

      return hash.slice(*repository_columns)
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def get_file_list(repository, token = nil)
      tree = api_client(token).tree(repository.full_name, repository.default_branch, recursive: true).tree
      tree.select{|item| item.type == 'blob' }.map{|file| file.path }
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def get_file_contents(path, token = nil)
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

    def download_tags(token = nil)
      existing_tag_names = repository.tags.pluck(:name)
      tags = api_client(token).refs(repository.full_name, 'tags')
      Array(tags).each do |tag|
        next unless tag && tag.is_a?(Sawyer::Resource) && tag['ref']
        download_tag(token, tag, existing_tag_names)
      end
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def download_tag(token, tag, existing_tag_names)
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

    private

    def api_client(token = nil, options = {})
      Octokit::Client.new({access_token: token, auto_paginate: true}.merge(options))
    end
  end
end
