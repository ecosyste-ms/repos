class Api::V1::TagsController < Api::V1::ApplicationController
  before_action :find_host

  def index
    @repository = @host.find_repository(params[:repository_id].downcase)
    if @repository.nil?
      return if render_shadowed_repository(params[:repository_id], 'tags')
      @host.sync_repository_async(params[:repository_id])
      raise ActiveRecord::RecordNotFound
    else
      unless @repository.full_name.downcase == params[:repository_id].downcase
        redirect_to api_v1_host_repository_tags_path(@host, @repository.full_name), status: :moved_permanently
        return
      end

      scope = @repository.tags

      scope = scope.order(*sanitize_orders(Tag.sortable_columns, default: 'published_at'))

      @pagy, @tags = pagy_countless(scope)
      fresh_when @tags, public: true
    end
  end

  def show
    @repository = @host.find_repository(params[:repository_id].downcase)
    raise ActiveRecord::RecordNotFound if @repository.nil?
    @tag = @repository.tags.find_by_name!(params[:id])
    fresh_when @tag, public: true
  end
end
