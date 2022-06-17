class RepositoriesController < ApplicationController
  def show
    @host = Host.find_by_name(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    @manifests = @repository.manifests.includes(:dependencies).order('kind DESC')
  end
end