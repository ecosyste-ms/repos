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

      scope = @repository.tags

      if params[:sort].present? || params[:order].present?
        sort = params[:sort] || 'published_at'
        order = params[:order] || 'desc'
        sort_options = sort.split(',').zip(order.split(',')).to_h
        scope = scope.order(sort_options)
      else
        scope = scope.order('published_at DESC')
      end

      @pagy, @tags = pagy(scope)
      fresh_when @tags, public: true
    end
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.find_repository(params[:repository_id].downcase)
    raise ActiveRecord::RecordNotFound if @repository.nil?
    @tag = @repository.tags.find_by_name!(params[:id])
    fresh_when @tag, public: true
  end
end