class Api::V1::ReleasesController < Api::V1::ApplicationController
  before_action :find_host

  def index
    @repository = @host.find_repository(params[:repository_id].downcase)
    if @repository.nil?
      @host.sync_repository_async(params[:id])
      raise ActiveRecord::RecordNotFound
    else
      unless @repository.full_name.downcase == params[:repository_id].downcase
        redirect_to api_v1_host_repository_releases_path(@host, @repository.full_name), status: :moved_permanently
        return
      end

      scope = @repository.releases

      if params[:sort].present? || params[:order].present?
        sort = params[:sort] || 'published_at'
        order = params[:order] || 'desc'
        sort_options = sort.split(',').zip(order.split(',')).to_h
        scope = scope.order(sort_options)
      else
        scope = scope.order('published_at DESC')
      end

      @pagy, @releases = pagy_countless(scope)
      fresh_when @releases, public: true
    end
  end

  def show
    @repository = @host.find_repository(params[:repository_id].downcase)
    raise ActiveRecord::RecordNotFound if @repository.nil?
    @release = @repository.releases.find_by_tag_name!(params[:id])
    fresh_when @release, public: true
  end
end
