class Api::V1::TagsController < Api::V1::ApplicationController
  def index
    @host = Host.find_by_name(params[:host_id])
    @repository = @host.repositories.find_by_full_name(params[:repository_id])
    @pagy, @tags = pagy(@repository.tags)
  end
end