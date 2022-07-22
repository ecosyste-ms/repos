class Api::V1::ManifestsController < Api::V1::ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])

    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    
    @pagy, @manifests = pagy(@repository.manifests.includes(:dependencies))
  end
end