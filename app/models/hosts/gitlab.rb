module Hosts
  class Gitlab < Base
    class GitlabAnonClient
      def initialize(endpoint:)
        Rails.logger.debug("Gitlab: Using anonymous client for endpoint #{endpoint}")
        @endpoint = endpoint
        @gitlab_client = ::Gitlab.client(endpoint: endpoint)
      end

      def faraday_client
        connection = Faraday.new do |faraday|
          faraday.use Faraday::FollowRedirects::Middleware

          faraday.adapter Faraday.default_adapter
        end
      end

      def tags(id_or_full_name, &block)
        # return an iterator if no block is given
        return enum_for(__callee__, id_or_full_name) unless block

        per_page = 100
        page = 1
        loop do
          url = "#{@endpoint}/projects/#{CGI.escape(id_or_full_name.to_s)}/repository/tags?search=&per_page=#{per_page}&page=#{page}"
          Rails.logger.debug("Gitlab: Fetching tags from URL: #{url}")
          response = faraday_client.get(url)
          tags = JSON.parse(response.body, object_class: OpenStruct)
          Rails.logger.debug("Gitlab: Fetched #{tags.count} tags")
          tags.each do |tag|
            yield tag
          end
          return if tags.count < per_page
          page += 1
        end
      end

      def project(id_or_full_name, license: false)
        url = "#{@endpoint}/projects/#{CGI.escape(id_or_full_name.to_s)}?license=#{license}"
        Rails.logger.debug("Gitlab[project]: Fetching project from URL: #{url}")

        response = faraday_client.get(url)
        project = JSON.parse(response.body, object_class: OpenStruct)
        return nil if project.nil? || project.empty?
        project.visibility = "public" # We get it from a nonauthenticated public endpoint
        project
      rescue JSON::ParserError
        nil
      end

      def projects(per_page:, archived:, id_before: nil, id_after: nil, simple:, page: 1, order_by: nil, sort: nil)
        if id_before
          sort ||= "desc"
          order_by ||= "id"
        elsif id_after
          sort ||= "asc"
          order_by ||= "id"
        else
          sort ||= "desc"
          order_by ||= "id"
        end
        url = "#{@endpoint}/projects?per_page=#{per_page}&archived=#{archived}&id_before=#{id_before}&id_after=#{id_after}&simple=#{simple}&page=#{page}&order_by=#{order_by}&sort=#{sort}"
        Rails.logger.debug("Gitlab[projects]: Fetching projects from URL: #{url}")

        response = faraday_client.get(url)
        JSON.parse(response.body, object_class: OpenStruct)
      rescue JSON::ParserError
        nil
      end

      def user(username)
        # 403 forbidden
        url = "#{@endpoint}/users/#{CGI.escape(username.to_s)}"
        Rails.logger.debug("Gitlab[user]: Fetching user from URL: #{url}")

        response = faraday_client.get(url)
        JSON.parse(response.body)
      rescue JSON::ParserError
        nil
      end

      def group(username, with_projects:)
        url = "#{@endpoint}/groups/#{CGI.escape(username)}?with_projects=#{with_projects}"
        Rails.logger.debug("Gitlab[group]: Fetching group from URL: #{url}")

        response = faraday_client.get(url)
        JSON.parse(response.body)
      rescue JSON::ParserError
        nil
      end

      def group_projects(username, per_page:, archived:, simple:, include_subgroups:)
        url = "#{@endpoint}/groups/#{CGI.escape(username)}/projects?per_page=#{per_page}&archived=#{archived}&simple=#{simple}&include_subgroups=#{include_subgroups}"
        Rails.logger.debug("Gitlab[group_projects]: Fetching group projects from URL: #{url}")

        response = faraday_client.get(url)
        JSON.parse(response.body, object_class: OpenStruct)
      rescue JSON::ParserError
        nil
      end

      def get(path, options = {})
        url = "#{@endpoint}#{path}"
        Rails.logger.debug("Gitlab[get]: Fetching from URL: #{url}")

        response = faraday_client.get(url)
        JSON.parse(response.body)
      rescue JSON::ParserError
        nil
      end

      def method_missing(method, *args, &block)
        Rails.logger.warn("Gitlab: delegating unauthenticated, non implemented method #{method} to Gitlab client, it should fail.")
        @gitlab_client.send(method, *args, &block)
      end
    end

    IGNORABLE_EXCEPTIONS = [::Gitlab::Error::NotFound,
      ::Gitlab::Error::Forbidden,
      ::Gitlab::Error::Unauthorized,
      ::Gitlab::Error::InternalServerError,
      ::Gitlab::Error::Parsing,
      ::Gitlab::Error::BadGateway]

    def self.api_missing_error_class
      ::Gitlab::Error::NotFound
    end

    def avatar_url(repository, _size = 60)
      repository.logo_url
    end

    def html_url(repository)
      "#{@host.url}/#{repository.full_name}"
    end

    def forks_url(repository)
      "#{url(repository)}/forks"
    end

    def contributors_url(repository)
      "#{url(repository)}/graphs/#{repository.default_branch}"
    end

    def blob_url(repository, sha = nil)
      sha ||= repository.default_branch
      "#{url(repository)}/blob/#{sha}/"
    end

    def commits_url(repository, author = nil)
      "#{url(repository)}/commits/#{repository.default_branch}"
    end

    def tag_url(repository, tag_name)
      "#{url(repository)}/-/tags/#{tag_name}"
    end

    def download_url(repository, branch = nil, kind = "branch")
      branch = repository.default_branch if branch.nil?
      branch = "master" if branch.blank?
      name = repository.full_name.split("/").last
      "#{@host.url}/#{repository.full_name}/-/archive/#{branch}/#{name}-#{branch}.zip"
    end

    def get_file_list(repository)
      files_and_folders = JSON.parse(Faraday.get("#{ARCHIVES_DOMAIN}/api/v1/archives/list?url=#{CGI.escape(download_url(repository))}").body)
      files_and_folders.reject { |f| files_and_folders.any? { |ff| ff.starts_with?(f + "/") } }
    rescue
      []
    end

    def topic_url(topic)
      "#{@host.url}/explore/projects/topics/#{topic}"
    end

    def get_file_contents(repository, path)
      file = api_client.get_file(repository.full_name, path, repository.default_branch)
      {
        sha: file.commit_id,
        content: Base64.decode64(file.content)
      }
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def download_readme(repository)
      files = api_client.tree(repository.full_name)
      paths = files.map(&:path)
      readme_path = paths.select { |path| path.match(/^readme/i) }.sort { |path| Readme.supported_format?(path) ? 0 : 1 }.first
      return if readme_path.nil?
      file = get_file_contents(readme_path)
      return unless file.present?
      content = Readme.format_markup(readme_path, file[:content])
      return unless content.present?

      if repository.readme.nil?
        repository.create_readme(html_body: content)
      else
        repository.readme.update(html_body: content)
      end
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def download_tags(repository)
      existing_tag_names = repository.tags.pluck(:name)
      remote_tags = api_client.tags(repository.full_name).each do |tag|
        next if existing_tag_names.include?(tag.name)
        next if tag.commit.nil?
        repository.tags.create({
          name: tag.name,
          kind: "tag",
          sha: tag.commit.id,
          published_at: tag.commit.committed_date
        })
      end
      repository.update_columns(tags_last_synced_at: Time.now, tags_count: repository.tags.count)
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def recently_changed_repo_names(since = 1.hour)
      target_time = Time.now - since
      names = []
      page = 1

      repos = load_repo_names(page, "updated_at")
      return [] unless repos.present?
      oldest = repos.last["last_activity_at"]
      names += repos.map { |repo| repo["path_with_namespace"] }

      while oldest > target_time
        page += 1
        repos = load_repo_names(page, "updated_at")
        break unless repos.present?
        oldest = repos.last["last_activity_at"]
        names += repos.map { |repo| repo["path_with_namespace"] }
      end

      names.uniq
    end

    def load_repo_names(page_number = 1, order = "created_at")
      api_client.projects(per_page: 100, page: page_number, order_by: order, archived: false, simple: true)
    rescue *IGNORABLE_EXCEPTIONS
      []
    end

    def recursive_gitlab_repos(page_number = 1, limit = 5, order = "created_asc")
      return if limit.zero?

      if names.any?
        limit -= 1
        recursive_gitlab_repos(page_number.to_i + 1, limit, order)
      end
    end

    def api_token
      @api_token ||= REDIS.get("gitlab_token:#{@host.id}")
    end

    def api_client
      if api_token.present?
        ::Gitlab.client(endpoint: "#{@host.url}/api/v4", private_token: api_token)
      else
        GitlabAnonClient.new(endpoint: "#{@host.url}/api/v4")
      end
    end

    def fetch_repository(full_name)
      project = api_client.project(full_name, license: true)
      return nil if project.nil? || project.empty?
      return nil if project.visibility != "public"

      full_hash = project.to_h.with_indifferent_access

      namespace = full_hash[:namespace]&.to_h&.with_indifferent_access

      return nil if namespace && namespace[:kind] == "user" && ENV["SKIP_USER_REPOS"]

      repo_hash = full_hash.slice(:id, :description, :created_at, :name, :open_issues_count, :forks_count, :default_branch, :archived, :topics)

      repo_hash.merge!({
        uuid: project.id,
        full_name: project.path_with_namespace,
        owner: project.path_with_namespace.try(:split, "/").try(:first),
        fork: project.try(:forked_from_project).present?,
        updated_at: project.last_activity_at,
        stargazers_count: project.star_count,
        has_issues: project.try(:issues_enabled),
        has_wiki: project.try(:wiki_enabled),
        scm: "git",
        private: project.visibility != "public",
        pull_requests_enabled: project.try(:merge_requests_enabled),
        logo_url: project.avatar_url,
        parent: {
          full_name: project.try(:forked_from_project).try(:path_with_namespace)
        }
      })

      repo_hash[:license] = project.license.try(:key)
      return nil if repo_hash[:full_name].nil?
      repo_hash.slice(*repository_columns)
    end

    def crawl_repositories_async
      last_id = REDIS.get("gitlab_last_id:#{@host.id}")
      repos = api_client.projects(per_page: 100, archived: false, id_before: last_id, simple: true)
      if repos.present? && repos.any?
        repos.each { |repo| @host.sync_repository_async(repo["path_with_namespace"]) }
        REDIS.set("gitlab_last_id:#{@host.id}", repos.last["id"])
      end
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def crawl_repositories
      # legacy way to synchronize on ecosyste.ms
      crawl_repositories_backwards
    end

    def crawl_repositories_two_ways
      # new experimental way to synchronize
      if ! crawl_repositories_backwards
        crawl_repositories_forward
      end
    end

    def crawl_repositories_backwards
      last_id = REDIS.get("gitlab_last_id:#{@host.id}")
      repos = api_client.projects(per_page: 100, archived: false, id_before: last_id, simple: true)
      if repos.present? && repos.any?
        repos.reject! { |repo| repo.dig("namespace", "kind") == "user" } if ENV["SKIP_USER_REPOS"]
        repos.each { |repo| @host.sync_repository(repo["path_with_namespace"], uuid: repo["id"]) }
        REDIS.set("gitlab_last_id:#{@host.id}", repos.last["id"])
        return true
      end
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def crawl_repositories_forward
      recent_id = REDIS.get("gitlab_recent_id:#{@host.id}")
      if recent_id.nil?
        recent_id = @host.repositories.maximum(:uuid)
      end
      repos = api_client.projects(per_page: 100, archived: false, id_after: recent_id, simple: true)
      repos.reject! { |repo| repo.dig("namespace", "kind") == "user" } if ENV["SKIP_USER_REPOS"]
      if repos.present? && repos.any?
        repos.each { |repo| @host.sync_repository(repo["path_with_namespace"], uuid: repo["id"]) }
        REDIS.set("gitlab_recent_id:#{@host.id}", repos.last["id"])
      end
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end


    def load_owner_repos_names(owner)
      repos = if owner.user?
        api_client.user_projects(owner.login, per_page: 100, archived: false, simple: true)
      else
        api_client.group_projects(owner.login, per_page: 100, archived: false, simple: true, include_subgroups: true)
      end
      
      return [] unless repos.present?
      
      repos.map { |repo| repo["path_with_namespace"] }
    rescue *IGNORABLE_EXCEPTIONS
      []
    end

    def fetch_owner(login)
      search = api_client.get "/users?username=#{login}"
      if search.present? && search.is_a?(Array) && search.first.present?
        user = search.first.to_hash
        id = user["id"]
        user_response = api_client.user(id)
        return nil if user_response.nil?
        user_hash = user_response.to_hash
        return nil if user_hash.nil?
        {
          uuid: "user-#{user_hash["id"]}",
          login: user_hash["username"],
          name: user_hash["name"],
          website: user_hash["website_url"],
          location: user_hash["location"],
          description: user_hash["bio"],
          avatar_url: user_hash["avatar_url"],
          kind: "user"
        }
      else
        group = api_client.group(login, with_projects: false)
        return nil if group.nil?
        {
          uuid: "organization-#{group["id"]}",
          login: group["path"],
          name: group["name"],
          description: group["description"],
          avatar_url: group["avatar_url"],
          kind: "organization"
        }
      end
    rescue *IGNORABLE_EXCEPTIONS => e
      pp e
      nil
    end

    def host_version
      api_client.version.version
    rescue
      nil
    end
  end
end
