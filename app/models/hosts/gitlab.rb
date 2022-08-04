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
      "https://gitlab.com/#{repository.full_name}"
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

    def download_url(repository, branch = nil)
      branch = repository.default_branch if branch.nil?
      name = repository.full_name.split('/').last
      "https://gitlab.com/#{repository.full_name}/-/archive/#{branch}/#{name}-#{branch}.zip"
    end

    def get_file_list(repository)
      tree = api_client.tree(repository.full_name, recursive: true)
      tree.select{|item| item.type == 'blob' }.map{|file| file.path }
    rescue *IGNORABLE_EXCEPTIONS
      nil
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
      remote_tags = api_client.tags(repository.full_name).auto_paginate do |tag|
        next if existing_tag_names.include?(tag.name)
        next if tag.commit.nil?
        repository.tags.create({
          name: tag.name,
          kind: "tag",
          sha: tag.commit.id,
          published_at: tag.commit.committed_date
        })
      end
      repository.projects.find_each(&:forced_save) if remote_tags.present?
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

      return names
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
      ::Gitlab.client(endpoint: 'https://gitlab.com/api/v4', private_token: ENV['GITLAB_KEY'])
    end

    def fetch_repository(full_name)
      project = api_client.project(full_name)
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
      return repo_hash.slice(*repository_columns)
    rescue *IGNORABLE_EXCEPTIONS
      nil
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
  end
end
