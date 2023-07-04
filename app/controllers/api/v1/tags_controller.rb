class Api::V1::TagsController < Api::V1::ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:repository_id].downcase)
    if @repository.nil?
      @host.sync_repository_async(params[:id])
      raise ActiveRecord::RecordNotFound
    else
      if @repository.full_name.downcase != params[:repository_id].downcase
        redirect_to api_v1_host_repository_tags_path(@host, @repository.full_name), status: :moved_permanently
        return
      end
      @pagy, @tags = pagy(@repository.tags.order('published_at DESC'))
    end
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:repository_id].downcase)
    @tag = @repository.tags.find_by_name!(params[:id])
  end
end