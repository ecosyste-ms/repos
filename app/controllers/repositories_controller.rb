class RepositoriesController < ApplicationController
  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:id].downcase)
    fresh_when(@repository, public: true)
    if @repository.nil?
      @host.sync_repository_async(params[:id])
      raise ActiveRecord::RecordNotFound and return
    else
      if @repository.full_name.downcase != params[:id].downcase
        redirect_to(host_repository_path(@host, @repository.full_name), status: :moved_permanently) and return
      end
      
      @tags = @repository.tags.order('published_at DESC')
      @sha = params[:sha] || @repository.default_branch
      if params[:sha] && @tags.map(&:name).include?(params[:sha])
        @tag = @tags.find{|t| t.name == params[:sha] }
        @manifests = @tag.manifests.includes(:dependencies).order('kind DESC')
      else
        @manifests = @repository.manifests.includes(:dependencies).order('kind DESC')
      end
    end
  end

  def funding
    # disabled
  end
end