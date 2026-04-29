class Api::V1::HostsController < Api::V1::ApplicationController
  before_action :find_host_by_id, only: [:show, :stats]

  def index
    scope = Host.all.order('repositories_count DESC')
    @pagy, @hosts = pagy(scope)
    fresh_when @hosts, public: true
  end

  def show
    fresh_when @host, public: true
  end

  def stats
    render json: host_stats(@host)
  end

  def global_stats
    render json: {
      repositories_count: Repository.count,
      hosts_count: Host.count,
      owners_count: Owner.visible.count,
      top_repositories: repository_stats(Repository.all),
      top_owners: owner_stats(Owner.visible)
    }
  end

  private

  def host_stats(host)
    repositories = host.repositories
    owners = host.owners.visible

    {
      host: host.name,
      repositories_count: repositories.count,
      owners_count: owners.count,
      top_repositories: repository_stats(repositories),
      top_owners: owner_stats(owners)
    }
  end

  def repository_stats(scope)
    scope.order(Arel.sql('stargazers_count DESC NULLS LAST')).limit(10).map do |repository|
      {
        full_name: repository.full_name,
        stargazers_count: repository.stargazers_count,
        forks_count: repository.forks_count,
        subscribers_count: repository.subscribers_count,
        open_issues_count: repository.open_issues_count,
        pushed_at: repository.pushed_at
      }
    end
  end

  def owner_stats(scope)
    scope.order(Arel.sql('total_stars DESC NULLS LAST, repositories_count DESC NULLS LAST')).limit(10).map do |owner|
      {
        login: owner.login,
        kind: owner.kind,
        repositories_count: owner.repositories_count,
        total_stars: owner.total_stars
      }
    end
  end
end