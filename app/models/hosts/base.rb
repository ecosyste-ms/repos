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

    def url(repository)
      "#{@host.url}/#{repository.full_name}"
    end

    def issues_url
      "#{url}/issues"
    end

    def source_url(repository)
      "#{@host.url}/#{repository.source_name}"
    end

    def raw_url(sha = nil)
      sha ||= repository.default_branch
      "#{url}/raw/#{sha}/"
    end

    def compare_url(branch_one, branch_two)
      "#{url}/compare/#{branch_one}...#{branch_two}"
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

    def avatar_url(size = 60)
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
        end
        
      rescue *Array(self.class.api_missing_error_class)
        repository.destroy
      rescue *self.class::IGNORABLE_EXCEPTIONS
        nil
      end
    end

    def gather_maintenance_stats_async
      RepositoryMaintenanceStatWorker.enqueue(repository.id, priority: :medium)
    end

    def gather_maintenance_stats
      # should be overwritten in individual repository_host class
      []
    end

    private

    attr_reader :repository

    def add_metrics_to_repo(results)
      # create one hash with all results
      results.reduce(Hash.new, :merge).each do |category, value|
          unless value.nil?
              stat = repository.repository_maintenance_stats.find_or_create_by(category: category.to_s)
              stat.update!(value: value.to_s)
              stat.touch unless stat.changed?  # we always want to update updated_at for later querying
          end
      end
    end
  end
end
