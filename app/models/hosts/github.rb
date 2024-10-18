module Hosts
  class Github < Base
    IGNORABLE_EXCEPTIONS = [
      Octokit::Unauthorized,
      Octokit::InvalidRepository,
      # Octokit::RepositoryUnavailable,
      # Octokit::NotFound,
      Octokit::Conflict,
      # Octokit::Forbidden,
      Octokit::InternalServerError,
      Octokit::BadGateway,
      # Octokit::UnavailableForLegalReasons
      Octokit::SAMLProtected
    ]

    def self.api_missing_error_class
      [
        Octokit::NotFound,
        Octokit::RepositoryUnavailable,
        Octokit::UnavailableForLegalReasons
      ]
    end

    def icon
      "github"
    end

    def token_set_key
      "github_tokens"
    end

    def list_tokens
      REDIS.smembers(token_set_key)
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
      list_tokens.each do |token|
        api_client(token).rate_limit!
      rescue Octokit::Unauthorized, Octokit::AccountSuspended
        puts "Removing token #{token}"
        remove_token(token)
      end
    end

    def html_url(repository)
      "https://github.com/#{repository.full_name}"
    end

    def avatar_url(repository, size = 40)
      "https://github.com/#{repository.owner}.png#{"?s=#{size}" if size}"
    end

    def download_url(repository, branch = nil, kind = "branch")
      if kind == "branch"
        branch = repository.default_branch if branch.nil?
        "https://codeload.github.com/#{repository.full_name}/tar.gz/refs/heads/#{branch}"
      else
        "https://codeload.github.com/#{repository.full_name}/tar.gz/#{branch}"
      end
    end

    def tag_url(repository, tag_name)
      "#{url(repository)}/releases/tag/#{tag_name}"
    end

    def watchers_url(repository)
      "#{url(repository)}/watchers"
    end

    def forks_url(repository)
      "#{url(repository)}/network"
    end

    def stargazers_url(repository)
      "#{url(repository)}/stargazers"
    end

    def contributors_url(repository)
      "#{url(repository)}/graphs/contributors"
    end

    def blob_url(repository, sha = nil)
      sha ||= repository.default_branch
      "#{url(repository)}/blob/#{sha}/"
    end

    def commits_url(repository, author = nil)
      author_param = author.present? ? "?author=#{author}" : ""
      "#{url(repository)}/commits#{author_param}"
    end

    def topic_url(topic)
      "#{@host.url}/topics/#{topic}"
    end

    def fetch_repository(id_or_name)
      id_or_name = id_or_name.to_i if /\A\d+\Z/.match?(id_or_name)
      hash = api_client.repo(id_or_name, accept: "application/vnd.github.drax-preview+json,application/vnd.github.mercy-preview+json").to_hash.with_indifferent_access
      return nil if hash[:private]
      map_repository_data(hash)
    end

    def map_repository_data(hash)
      hash[:scm] = "git"
      hash[:uuid] = hash[:id]
      hash[:license] = hash[:license][:key] if hash[:license]
      hash[:owner] = hash[:owner][:login]
      hash[:pull_requests_enabled] = true
      hash[:template] = hash[:is_template]
      hash[:template_full_name] = hash[:template_repository][:full_name] if hash[:template_repository]

      if hash[:fork] && hash[:parent]
        hash[:source_name] = hash[:parent][:full_name]
      end

      hash = hash.transform_values { |v| v.is_a?(String) ? v.gsub(/\000/, "") : v }

      hash.slice(*repository_columns)
    end

    def get_file_list(repository)
      tree = api_client.tree(repository.full_name, repository.default_branch, recursive: true).tree
      tree.select { |item| item.type == "blob" }.map { |file| file.path }
    rescue *IGNORABLE_EXCEPTIONS, Octokit::NotFound, Octokit::RepositoryUnavailable, Octokit::UnavailableForLegalReasons
      nil
    end

    def get_file_contents(repository, path)
      file = api_client.contents(repository.full_name, path: path)
      {
        sha: file.sha,
        content: file.content.present? ? Base64.decode64(file.content) : file.content
      }
    rescue URI::InvalidURIError
      nil
    rescue *IGNORABLE_EXCEPTIONS, Octokit::NotFound, Octokit::RepositoryUnavailable, Octokit::UnavailableForLegalReasons
      nil
    end

    def download_tags(repository)
      existing_tag_names = repository.tags.pluck(:name)
      tags = fetch_tags(repository)
      # TODO upsert the whole array
      Array(tags).each do |tag|
        next if existing_tag_names.include?(tag[:name])
        repository.tags.create(tag)
      end
      repository.update_columns(tags_last_synced_at: Time.now, tags_count: repository.tags.count)
    rescue *IGNORABLE_EXCEPTIONS, Octokit::NotFound, Octokit::RepositoryUnavailable, Octokit::UnavailableForLegalReasons
      nil
    end

    def download_releases(repository)
      existing_releases_uuids = repository.releases.pluck(:uuid)
      releases = fetch_releases(repository)
      # TODO upsert the whole array
      releases.each do |release|
        next if existing_releases_uuids.include?(release[:uuid].to_s)
        puts release[:tag_name]
        repository.releases.create(release)
      end
      nil
    rescue *IGNORABLE_EXCEPTIONS, Octokit::NotFound, Octokit::RepositoryUnavailable, Octokit::UnavailableForLegalReasons
      nil
    end

    def fetch_releases(repository)
      api_client.releases(repository.full_name).map do |release|
        {
          uuid: release.id,
          tag_name: release.tag_name,
          target_commitish: release.target_commitish,
          name: release.name,
          body: release.body.try(:delete, "\u0000"),
          draft: release.draft,
          prerelease: release.prerelease,
          created_at: release.created_at,
          published_at: release.published_at,
          author: release.author.try(:login),
          assets: release.assets.map { |a| a.to_hash.with_indifferent_access },
          last_synced_at: Time.now
        }
      end
    rescue *IGNORABLE_EXCEPTIONS, Octokit::NotFound, Octokit::UnprocessableEntity, Octokit::RepositoryUnavailable, Octokit::UnavailableForLegalReasons
      []
    end

    def load_owner_repos_names(owner)
      api_client.repos(owner.login, type: "all").map { |repo| repo[:full_name] }
    rescue *IGNORABLE_EXCEPTIONS, Octokit::NotFound
      []
    end

    def fetch_tags(repository)
      tags = []
      fetch_tags_graphql(repository).tap do |res|
        return if res[:data].nil? || res[:data][:repository].nil? || res[:data][:repository][:refs].nil?
        tags += map_tags(res)
        while res.dig(:data, :repository, :refs, :pageInfo, :hasNextPage)
          res = fetch_tags_graphql(repository, res[:data][:repository][:refs][:pageInfo][:endCursor])
          tags += map_tags(res)
        end
      end
      tags
    end

    def fetch_tags_graphql(repository, cursor = nil)
      query = <<-GRAPHQL
        {
          repository(owner: "#{repository.owner}", name: "#{repository.project_name}") {
            refs(
              refPrefix: "refs/tags/"
              orderBy: {field: TAG_COMMIT_DATE, direction: DESC}
              first: 100
              #{", after: \"#{cursor}\"" if cursor.present?}
            ) {
              pageInfo{
                startCursor
                hasNextPage
                endCursor
              }
              nodes {
                name
                target {
                  __typename
                  ... on Commit{
                    oid
                    committer{
                      ... on GitActor {
                        date
                      }
                    }
                  }
                  ... on Tag {
                    target {
                      ... on GitObject {
                        oid
                      }
                    }
                    tagger {
                      ... on GitActor {
                        date
                      }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
      res = api_client.post("/graphql", {query: query}.to_json).to_h
    end

    def map_tags(tags)
      return [] unless tags && tags[:data] && tags[:data][:repository] && tags[:data][:repository][:refs]
      tags[:data][:repository][:refs][:nodes].map do |tag|
        next if tag.nil? || tag[:target].nil?
        if tag[:target][:__typename] == "Tag"
          {
            name: tag[:name],
            sha: tag[:target][:target][:oid],
            published_at: tag[:target][:tagger][:date],
            kind: "tag"
          }
        elsif tag[:target][:__typename] == "Commit"
          {
            name: tag[:name],
            sha: tag[:target][:oid],
            published_at: tag[:target][:committer][:date],
            kind: "commit"
          }
        end
      end.compact
    end

    def fetch_owner(login)
      query = <<-GRAPHQL
        {
          repositoryOwner(login: "#{login}") {
            login
            __typename
            ... on User {
              hasSponsorsListing
              name
              databaseId
              bio
              email
              websiteUrl
              location
              twitterUsername
              avatarUrl
              company
              followers {
                totalCount
              }
              following {
                totalCount
              } 
            }
            ... on Organization{
              hasSponsorsListing
              name
              databaseId
              description
              email
              websiteUrl
              location
              twitterUsername
              avatarUrl
            }
          }
        }
      GRAPHQL
      res = api_client.post("/graphql", {query: query}.to_json).to_h
      return nil unless res && res[:data] && res[:data][:repositoryOwner].present?
      kind = res[:data][:repositoryOwner][:__typename].downcase

      hash = {
        login: res[:data][:repositoryOwner][:login],
        name: res[:data][:repositoryOwner][:name],
        uuid: res[:data][:repositoryOwner][:databaseId],
        description: res[:data][:repositoryOwner][:description] || res[:data][:repositoryOwner][:bio],
        email: res[:data][:repositoryOwner][:email],
        website: res[:data][:repositoryOwner][:websiteUrl],
        location: res[:data][:repositoryOwner][:location],
        twitter: res[:data][:repositoryOwner][:twitterUsername],
        company: res[:data][:repositoryOwner][:company],
        kind: kind,
        avatar_url: res[:data][:repositoryOwner][:avatarUrl],
        followers: res.dig(:data, :repositoryOwner, :followers, :totalCount),
        following: res.dig(:data, :repositoryOwner, :following, :totalCount),
        metadata: {
          has_sponsors_listing: res[:data][:repositoryOwner][:hasSponsorsListing]
        }
      }
      if kind == "organization"
        begin
          rest_res = api_client.organization(login)
          hash[:followers] = rest_res[:followers]
          hash[:following] = rest_res[:following]
        rescue
          nil
        end
      elsif ENV["SKIP_USER_REPOS"].present?
        return nil
      end
      hash
    end

    def recently_changed_repo_names(since = 1.hour)
      names = []

      first_response = load_repo_names
      return [] if first_response.blank?
      most_recent = first_response["newest"]["created_at"]
      target_time = Time.parse(most_recent) - since
      next_id = first_response["oldest"]["id"]

      next_response = load_repo_names(next_id)
      names = (names + next_response["names"]).uniq
      next_id = next_response["oldest"]["id"]

      while Time.parse(next_response["oldest"]["created_at"]) > target_time
        next_response = load_repo_names(next_id)
        names = (names + next_response["names"]).uniq
        next_id = next_response["oldest"]["id"]
      end

      names.uniq
    end

    def sync_repos_with_tags
      data = load_repos_with_tags
      names = data.map { |r| r["repository"] }.uniq
      host = Host.find_by_name("GitHub")
      names.each do |name|
        repository = host.find_repository(name.downcase)
        if repository
          repository.download_tags_async
        else
          host.sync_repository_async(name)
        end
      end
    end

    def load_repos_with_tags(id = nil)
      url = "#{TIMELINE_DOMAIN}/api/v1/events?per_page=100&event_type=ReleaseEvent&before=#{id}"
      begin
        resp = Faraday.get(url) do |req|
          req.options.timeout = 5
        end

        if resp.success?
          Oj.load(resp.body)
        else
          []
        end
      rescue Faraday::Error
        []
      end
    end

    def load_repo_names(id = nil)
      puts "loading repo names since #{id}"
      url = "#{TIMELINE_DOMAIN}/api/v1/events/repository_names"
      url = "#{url}?before=#{id}" if id.present?
      begin
        resp = Faraday.get(url) do |req|
          req.options.timeout = 5
        end

        if resp.success?
          Oj.load(resp.body)
        else
          {}
        end
      rescue Faraday::Error
        {}
      end
    end

    def events_for_repo(full_name, event_type: nil, per_page: 100)
      url = "#{TIMELINE_DOMAIN}/api/v1/events/#{full_name}?per_page=#{per_page}"
      url = "#{url}&event_type=#{event_type}" if event_type.present?

      begin
        resp = Faraday.get(url) do |req|
          req.options.timeout = 5
        end

        if resp.success?
          Oj.load(resp.body)
        else
          {}
        end
      rescue Faraday::Error
        {}
      end
    end

    def attempt_load_from_timeline(full_name)
      events = events_for_repo(full_name, event_type: "PullRequestEvent", per_page: 1)
      return nil if events.blank?
      events.first["payload"]["pull_request"]["base"]["repo"].to_hash.with_indifferent_access
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
