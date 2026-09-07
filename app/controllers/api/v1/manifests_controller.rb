class Api::V1::ManifestsController < Api::V1::ApplicationController
  before_action :find_host

  def index
    @repository = @host.find_repository(params[:repository_id].downcase)
    if @repository.nil?
      return if render_shadowed_repository(params[:repository_id], 'manifests')
      raise ActiveRecord::RecordNotFound
    end

    fresh_when(@repository, public: true)

    if params[:tag_id].present?
      @tag = @repository.tags.find_by_name!(params[:tag_id])
      @pagy, @manifests = pagy_countless(@tag.manifests.includes(:dependencies))
    else
      @pagy, @manifests = pagy_countless(@repository.manifests.includes(:dependencies))
    end
  end
end
