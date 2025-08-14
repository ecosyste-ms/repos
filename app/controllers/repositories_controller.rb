class RepositoriesController < ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    redirect_to host_path(@host)
  end
  
  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:id].downcase)
    
    if @repository.nil?
      @host.sync_repository_async(params[:id])
      raise ActiveRecord::RecordNotFound and return
    else
      raise ActiveRecord::RecordNotFound if @repository.owner_hidden?
      
      if @repository.full_name.downcase != params[:id].downcase
        redirect_to(host_repository_path(@host, @repository.full_name), status: :moved_permanently) and return
      end
    
      fresh_when(@repository, public: true)
      @tags = @repository.tags.order('published_at DESC').limit(100)
      @sha = params[:sha] || @repository.default_branch
    end
  end

  def dependencies
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:id].downcase)

    raise ActiveRecord::RecordNotFound if @repository.nil?
    raise ActiveRecord::RecordNotFound if @repository.owner_hidden?

    if @repository.full_name.downcase != params[:id].downcase
      redirect_to(host_repository_path(@host, @repository.full_name), status: :moved_permanently) and return
    end

    fresh_when(@repository, public: true)

    @tags = @repository.tags.order('published_at DESC').limit(100)
    @sha = params[:sha] || @repository.default_branch

    if params[:sha] && @tags.map(&:name).include?(params[:sha])
      @tag = @tags.find{|t| t.name == params[:sha] }
      @manifests = @tag.manifests.includes(:dependencies).order('kind DESC')
    else
      @manifests = @repository.manifests.includes(:dependencies).order('kind DESC')
    end
  end

  def readme
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:id].downcase)
    
    raise ActiveRecord::RecordNotFound if @repository.nil?
    raise ActiveRecord::RecordNotFound if @repository.owner_hidden?

    if @repository.full_name.downcase != params[:id].downcase
      redirect_to(host_repository_path(@host, @repository.full_name), status: :moved_permanently) and return
    end

    fresh_when(@repository, public: true)

    @tags = @repository.tags.order('published_at DESC').limit(100)
    @sha = params[:sha] || @repository.default_branch
  end

  def releases
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:id].downcase)
    
    raise ActiveRecord::RecordNotFound if @repository.nil?
    raise ActiveRecord::RecordNotFound if @repository.owner_hidden?

    if @repository.full_name.downcase != params[:id].downcase
      redirect_to(releases_host_repository_path(@host, @repository.full_name), status: :moved_permanently) and return
    end

    fresh_when(@repository, public: true)

    @tags = @repository.tags.order('published_at DESC').limit(100)
    @sha = params[:sha] || @repository.default_branch
    
    scope = @repository.releases

    if params[:sort] == 'semver'
      all_releases = scope.to_a.sort
      @pagy, @releases = pagy_array(all_releases, limit: 10)
    else
      @pagy, @releases = pagy(scope.order('published_at DESC'), limit: 10)
    end

    @sort = params[:sort] || 'date'
  end

  def funding
    # disabled
  end
end