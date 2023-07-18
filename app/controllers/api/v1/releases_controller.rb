class Api::V1::ReleasesController < Api::V1::ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:repository_id].downcase)
    if @repository.nil?
      @host.sync_repository_async(params[:id])
      raise ActiveRecord::RecordNotFound
    else
      if @repository.full_name.downcase != params[:repository_id].downcase
        redirect_to api_v1_host_repository_releases_path(@host, @repository.full_name), status: :moved_permanently
        return
      end
      @pagy, @releases = pagy(@repository.releases.order('published_at DESC'))
    end
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:repository_id].downcase)
    @release = @repository.releases.find_by_tag_name!(params[:id])
  end
end