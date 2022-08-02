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

    def recently_changed_repo_names(since=10.minutes)
      []
    end

    def avatar_url(repository, size = 60)
      raise NotImplementedError
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

    def update_from_host(repository, token = nil)
      begin
        r = self.fetch_repository(repository.id_or_name)
        return unless r.present?
        repository.uuid = r[:id] unless repository.uuid.to_s == r[:id].to_s
        if repository.full_name.downcase != r[:full_name].downcase
          clash = repository.host.repositories.where('lower(full_name) = ?', r[:full_name].downcase).first
          if clash && (!clash.host.host_instance.update_from_host(clash) || clash.status == "Removed")
            clash.destroy
          end
          repository.full_name = r[:full_name]
        end
        
        repository.assign_attributes r
        if repository.changed?
          repository.last_synced_at = Time.now
          repository.save! 
        else
          repository.update_column(:last_synced_at, Time.now)
        end
        
      rescue *Array(self.class.api_missing_error_class)
        repository.destroy
      rescue *self.class::IGNORABLE_EXCEPTIONS => e
        p e
        nil
      end
    end

    def crawl_repositories_async
      # to be implemented by subclasses
    end

    def crawl_repositories
      # to be implemented by subclasses
    end

    private

    attr_reader :repository
  end
end
