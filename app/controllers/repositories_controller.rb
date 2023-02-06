class RepositoriesController < ApplicationController
  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    if @repository.nil?
      @host.sync_repository_async(params[:id])
      raise ActiveRecord::RecordNotFound
    else
      @manifests = @repository.manifests.includes(:dependencies).order('kind DESC')
      @tags = @repository.tags.order('published_at DESC')
      @sha = params[:sha] || @repository.default_branch
    end
  end

  def funding
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    @dependencies = @repository.dependencies.includes(:manifest).order('kind DESC')
  end
end