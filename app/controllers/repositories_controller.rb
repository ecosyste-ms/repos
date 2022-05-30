class RepositoriesController < ApplicationController
  def show
    @host = Host.find_by_name(params[:host_id])
    @repository = @host.repositories.find_by_full_name(params[:id])
    @manifests = @repository.manifests.includes(:dependencies).order('kind DESC')
  end
end