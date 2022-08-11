# frozen_string_literal: true
module Hosts
  class Bitbucket < Base
    IGNORABLE_EXCEPTIONS = [
      Faraday::ResourceNotFound
    ]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'atlassian'
    end

    def avatar_url(repository, size = 60)
      "#{url(repository)}/#{repository.full_name}/avatar/#{size}"
    end

    def blob_url(repository, sha = nil)
      sha ||= repository.default_branch
      "#{url(repository)}/src/#{CGI.escape(sha)}/"
    end

    def download_url(repository, branch = nil)
      sha ||= repository.default_branch
      "#{url(repository)}/get/#{CGI.escape(sha)}.zip"
    end

    def commits_url(repository, author = nil)
      "#{url(repository)}/commits"
    end

    def compare_url(repository, branch_one, branch_two)
      "#{url(repository)}/compare/#{branch_two}..#{branch_one}#diff"
    end

    def get_file_list(repository)
      api_client.get("/2.0/repositories/#{repository.owner}/#{repository.project_name}/src").body['values']
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def get_file_contents(repository, path)
      file = api_client.get("/2.0/repositories/#{repository.owner}/#{repository.project_name}/src/#{CGI.escape(repository.default_branch)}/#{CGI.escape(path)}").body['values']
      {
        sha: file.node,
        content: file.data
      }
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def download_readme(repository)
      files = api_client.get("/2.0/repositories/#{repository.owner}/#{repository.project_name}/src").body['values']
      paths =  files.files.map(&:path)
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
      remote_tags = api_client.get("/2.0/repositories/#{repository.owner}/#{repository.project_name}/refs/tags").body['values']
      existing_tag_names = repository.tags.pluck(:name)
      remote_tags.each do |name, data|
        next if existing_tag_names.include?(name)
        repository.tags.create({
          name: name,
          kind: "tag",
          sha: data.raw_node,
          published_at: data.utctimestamp
        })
      end
      repository.projects.find_each(&:forced_save) if remote_tags.present?
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end

    def recursive_bitbucket_repos(url, limit = 5)
      return if limit.zero?
      r = Typhoeus::Request.new(url,
        method: :get,
        headers: { 'Accept' => 'application/json' }).run

      json = Oj.load(r.body)

      json['values'].each do |repo|
        CreateRepositoryWorker.perform_async('Bitbucket', repo['full_name'])
      end

      if json['values'].any? && json['next']
        limit = limit - 1
        REDIS.set 'bitbucket-after', Addressable::URI.parse(json['next']).query_values['after']
        recursive_bitbucket_repos(json['next'], limit)
      end
    end

    def api_client
      Faraday.new("https://api.bitbucket.org") do |conn|
        conn.request :authorization, :basic, ENV['BITBUCKET_USER'], ENV['BITBUCKET_KEY']
        conn.response :json 
      end
    end

    def fetch_repository(full_name)
      user_name, repo_name = full_name.split('/')
      project = api_client.get("/2.0/repositories/#{user_name}/#{repo_name.downcase}").body
      repo_hash = project.to_hash.with_indifferent_access.slice(:description, :uuid, :language, :full_name, :has_wiki, :has_issues, :scm)

      repo_hash.merge!({
        owner: project['owner']['username'],
        homepage: project['website'],
        fork: project['parent'].present?,
        created_at: project['created_on'],
        updated_at: project['updated_on'],
        default_branch: project.fetch('mainbranch', {}).try(:fetch, 'name', nil),
        private: project['is_private'],
        size: project['size'].to_f/1000,
        source_name: project.fetch('parent', {}).fetch('full_name', nil)
      })
    end
  end
end
