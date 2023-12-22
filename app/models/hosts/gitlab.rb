module Hosts
  class Gitlab < Base
    IGNORABLE_EXCEPTIONS = [::Gitlab::Error::NotFound,
                            ::Gitlab::Error::Forbidden,
                            ::Gitlab::Error::Unauthorized,
                            ::Gitlab::Error::InternalServerError,
                            ::Gitlab::Error::Parsing]

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

    def download_url(repository, branch = nil, kind = 'branch')
      branch = repository.default_branch if branch.nil?
      name = repository.full_name.split('/').last
      "#{@host.url}/#{repository.full_name}/-/archive/#{branch}/#{name}-#{branch}.zip"
    end

    def get_file_list(repository)
      files_and_folders = JSON.parse(Faraday.get("#{ARCHIVES_DOMAIN}/api/v1/archives/list?url=#{CGI.escape(download_url(repository))}").body)
      files_and_folders.reject{|f| files_and_folders.any?{|ff| ff.starts_with?(f+'/')}}
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
      paths =  files.map(&:path)
      readme_path = paths.select{|path| path.match(/^readme/i) }.sort{|path| Readme.supported_format?(path) ? 0 : 1 }.first
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

      repos = load_repo_names(page, 'updated_at')
      return [] unless repos.present?
      oldest = repos.last["last_activity_at"]
      names += repos.map{|repo| repo["path_with_namespace"] }

      while oldest > target_time
        page += 1
        repos = load_repo_names(page, 'updated_at')
        break unless repos.present?
        oldest = repos.last["last_activity_at"]
        names += repos.map{|repo| repo["path_with_namespace"] }
      end

      return names.uniq
    end

    def load_repo_names(page_number = 1, order = 'created_at')
      api_client.projects(per_page: 100, page: page_number, order_by: order, archived: false, simple: true)
    end

    def recursive_gitlab_repos(page_number = 1, limit = 5, order = "created_asc")
      return if limit.zero?

      if names.any?
        limit = limit - 1
        recursive_gitlab_repos(page_number.to_i + 1, limit, order)
      end
    end

    def api_client
      ::Gitlab.client(endpoint: "#{@host.url}/api/v4", private_token:  REDIS.get("gitlab_token:#{@host.id}"))
    end

    def fetch_repository(full_name)
      project = api_client.project(full_name, license: true)
      repo_hash = project.to_hash.with_indifferent_access.slice(:id, :description, :created_at, :name, :open_issues_count, :forks_count, :default_branch, :archived, :topics)

      repo_hash.merge!({
        uuid: project.id,
        full_name: project.path_with_namespace,
        owner: project.path_with_namespace.split('/').first,
        fork: project.try(:forked_from_project).present?,
        updated_at: project.last_activity_at,
        stargazers_count: project.star_count,
        has_issues: project.issues_enabled,
        has_wiki: project.wiki_enabled,
        scm: 'git',
        private: project.visibility != "public",
        pull_requests_enabled: project.merge_requests_enabled,
        logo_url: project.avatar_url,
        parent: {
          full_name: project.try(:forked_from_project).try(:path_with_namespace)
        }
      })

      repo_hash[:license] = project.license.try(:key)

      return repo_hash.slice(*repository_columns)
    end

    def crawl_repositories_async
      last_id = REDIS.get("gitlab_last_id:#{@host.id}")
      repos = api_client.projects(per_page: 100, archived: false, id_before: last_id, simple: true)
      if repos.present?
        repos.each{|repo| @host.sync_repository_async(repo["path_with_namespace"])  }
        REDIS.set("gitlab_last_id:#{@host.id}", repos.last["id"])
      end
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def crawl_repositories
      last_id = REDIS.get("gitlab_last_id:#{@host.id}")
      repos = api_client.projects(per_page: 100, archived: false, id_before: last_id, simple: true)
      if repos.present?
        repos.each{|repo| @host.sync_repository(repo["path_with_namespace"])  }
        REDIS.set("gitlab_last_id:#{@host.id}", repos.last["id"])
      end
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def load_owner_repos_names(owner)
      if owner.kind == 'user'
        api_client.user_projects(owner.login, per_page: 100, archived: false, simple: true).map{|repo| repo["path_with_namespace"] }
      else
        api_client.group_projects(owner.login, per_page: 100, archived: false, simple: true).map{|repo| repo["path_with_namespace"] }
      end
    rescue *IGNORABLE_EXCEPTIONS
      []
    end

    def fetch_owner(login)
      search = api_client.get "/users?username=#{login}"
      
      if search.present?
        user = search.first.to_hash
        id = user["id"]
        user_hash = api_client.user(id).to_hash

        {
          uuid: "user-#{user_hash["id"]}",
          login: user_hash["username"],
          name: user_hash["name"],
          website: user_hash["website_url"],
          location: user_hash["location"],
          description: user_hash["bio"],
          avatar_url: user_hash['avatar_url'],
          kind: 'user'
        }
      else
        group = api_client.group(login, with_projects: false)
        {
          uuid: "organization-#{group["id"]}",
          login: group["path"],
          name: group["name"],
          description: group["description"],
          avatar_url: group['avatar_url'],
          kind: 'organization'
        }
      end
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def host_version
      api_client.version.version
    rescue
      nil
    end
  end
end
