class RepositoriesController < ApplicationController
  def show
    @host = Host.find_by_name(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    raise ActiveRecord::RecordNotFound if @repository.nil?
    @manifests = @repository.manifests.includes(:dependencies).order('kind DESC')
  end
end