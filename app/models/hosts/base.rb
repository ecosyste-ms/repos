module Hosts
  class Base

    def repository_columns
      [
        :uuid,
        :full_name,                                                                       
        :owner,                                                                           
        :description,                                                                     
        :fork,                                                                            
        :created_at,                                                                      
        :updated_at,                                                                      
        :pushed_at,                                                                       
        :homepage,                                                                        
        :size,                                                                            
        :stargazers_count,                                                                                                                          
        :language,                                                                        
        :has_issues,                                                                      
        :forks_count,
        :mirror_url,
        :archived,
        :open_issues_count,
        :license,
        :topics,
        :default_branch,
        :subscribers_count,
        :private,
        :logo_url,
        :pull_requests_enabled,
        :scm,
        :status,
        :source_name,
        :template,
        :template_full_name
        # :allow_forking,
        # :has_projects,
        # :has_downloads,
        # :has_wiki,
        # :has_pages,
        # :is_template,
        # :disabled,
        # :visibility,
      ]
    end

    def initialize(host)
      @host = host
    end

    def icon
      @host.kind
    end

    def host_version
      nil
    end

    def purl_type
      @host.kind.downcase
    end

    def url(repository)
      "#{@host.url}/#{repository.full_name}"
    end

    def html_url(repository)
      url(repository)
    end

    def issues_url(repository)
      "#{url(repository)}/issues"
    end

    def source_url(repository)
      "#{@host.url}/#{repository.source_name}"
    end

    def raw_url(repository, sha = nil)
      sha ||= repository.default_branch
      "#{url(repository)}/raw/#{sha}/"
    end

    def compare_url(repository, branch_one, branch_two)
      "#{url(repository)}/compare/#{branch_one}...#{branch_two}"
    end

    def watchers_url
      nil
    end

    def forks_url
      nil
    end

    def stargazers_url
      nil
    end

    def contributors_url
      nil
    end

    def download_url(repository, branch = nil, kind = "branch")
      # For hosts that don't implement their own download_url, return nil
      # as we don't know their archive URL format
      nil
    end

    def topic_url(topic)
      nil
    end

    def recently_changed_repo_names(since=10.minutes)
      []
    end

    def avatar_url(repository, size = 60)
      nil
    end

    def get_file_list(repository)
      files_and_folders = JSON.parse(Faraday.get("#{ARCHIVES_DOMAIN}/api/v1/archives/list?url=#{CGI.escape(download_url(repository))}").body)
      files_and_folders.reject{|f| files_and_folders.any?{|ff| ff.starts_with?(f+'/')}}
    rescue
      []
    end

    def download_fork_source(token = nil)
      self.class.fetch_repository(repository.source_name, token) if download_fork_source?
    end

    def download_fork_source?
      repository.fork? && repository.source_name.present? && repository.source.nil?
    end

    def self.format(host_type)
      case host_type.try(:downcase)
      when 'github'
        'GitHub'
      when 'gitlab'
        'GitLab'
      when 'bitbucket'
        'Bitbucket'
      end
    end

    def formatted_host
      self.class.format(repository.host_type)
    end

    def repository_owner_class
      RepositoryOwner.const_get(repository.host_type.capitalize)
    end

    def repository_id_or_name(repository)
      repository.id_or_name
    end

    def update_from_host(repository, token = nil, retrying_clash = nil)
      puts "updating #{repository.full_name} (uuid: #{repository.uuid})"
      begin
        r = self.fetch_repository(repository_id_or_name(repository))
        return unless r.present?
        repository.uuid = r[:id] unless repository.uuid.to_s == r[:id].to_s
        if repository.full_name.downcase != r[:full_name].downcase
          clash = repository.host.repositories.find_by('lower(full_name) = ?', r[:full_name].downcase)
          if clash && (!retrying_clash && !clash.host.host_instance.update_from_host(clash, nil, true) || clash.status == "Removed")
            clash.destroy
          end
          repository.full_name = r[:full_name]
        end
        
        repository.assign_attributes r
        repository.tags_count = repository.tags.count if repository.tags_count.nil?
        if repository.changed?
          repository.ping_packages_async

          repository.last_synced_at = Time.now
          if repository.pushed_at_changed?
            repository.files_changed = true
          end
          begin
            repository.save! 
          rescue ActiveRecord::RecordNotUnique
            # duplicate repository
          end
          # repository.download_tags_async
        else
          repository.update_column(:last_synced_at, Time.now)
        end
        
      rescue *Array(self.class.api_missing_error_class) => e
        p e
        repository.destroy
      rescue *self.class::IGNORABLE_EXCEPTIONS => e
        p e
        nil
      end
    end

    def fetch_repository(id_or_name, token = nil)
      # to be implemented by subclasses
    end

    def crawl_repositories_async
      # to be implemented by subclasses
    end

    def crawl_repositories
      # to be implemented by subclasses
    end

    def download_tags(repository)
      # to be implemented by subclasses
    end

    def download_releases(repository)
      # to be implemented by subclasses
    end

    def blob_url(repository, sha = nil)
      # to be implemented by subclasses
    end

    private

    attr_reader :repository
  end
end
