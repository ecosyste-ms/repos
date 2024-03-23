class Api::V1::ManifestsController < Api::V1::ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])

    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    
    fresh_when(@repository, public: true)

    if params[:tag_id].present?
      @tag = @repository.tags.find_by_name!(params[:tag_id])
      @pagy, @manifests = pagy(@tag.manifests.includes(:dependencies))
    else
      @pagy, @manifests = pagy(@repository.manifests.includes(:dependencies))
    end
  end
end