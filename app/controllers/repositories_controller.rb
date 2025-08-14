class RepositoriesController < ApplicationController
  before_action :find_host
  before_action :find_and_validate_repository, except: [:index, :funding]
  before_action :setup_repository_data, except: [:index, :funding]

  def index
    redirect_to host_path(@host)
  end
  
  def show
    if @repository.nil?
      @host.sync_repository_async(params[:id])
      raise ActiveRecord::RecordNotFound and return
    end
  end

  def dependencies
    if params[:sha] && @tags.map(&:name).include?(params[:sha])
      @tag = @tags.find{|t| t.name == params[:sha] }
      @manifests = @tag.manifests.includes(:dependencies).order('kind DESC')
    else
      @manifests = @repository.manifests.includes(:dependencies).order('kind DESC')
    end
  end

  def readme
  end

  def releases
    scope = @repository.releases
    
    if params[:prefix].present?
      scope = scope.where("tag_name ILIKE ?", "#{params[:prefix]}%")
    end

    if params[:sort] == 'semver'
      all_releases = scope.to_a.sort
      @pagy, @releases = pagy_array(all_releases, limit: 10)
    else
      @pagy, @releases = pagy(scope.order('published_at DESC'), limit: 10)
    end

    @sort = params[:sort] || 'date'
    @prefix = params[:prefix]
  end

  def scorecard
    @scorecard = @repository.scorecard
  end

  def funding
    # disabled
  end

  private

  def find_host
    @host = Host.find_by_name!(params[:host_id])
  end

  def find_and_validate_repository
    @repository = @host.find_repository(params[:id].downcase)
    
    raise ActiveRecord::RecordNotFound if @repository.nil?
    raise ActiveRecord::RecordNotFound if @repository.owner_hidden?

    if @repository.full_name.downcase != params[:id].downcase
      redirect_path = case action_name
      when 'show'
        host_repository_path(@host, @repository.full_name)
      when 'dependencies'
        dependencies_host_repository_path(@host, @repository.full_name)
      when 'readme'
        readme_host_repository_path(@host, @repository.full_name)
      when 'releases'
        releases_host_repository_path(@host, @repository.full_name)
      when 'scorecard'
        scorecard_host_repository_path(@host, @repository.full_name)
      end
      redirect_to(redirect_path, status: :moved_permanently) and return
    end
  end

  def setup_repository_data
    fresh_when(@repository, public: true)
    @tags = @repository.tags.order('published_at DESC').limit(100)
    @sha = params[:sha] || @repository.default_branch
  end
end