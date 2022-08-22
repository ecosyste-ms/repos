class Api::V1::RepositoriesController < Api::V1::ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    scope = @host.repositories
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'last_synced_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('last_synced_at DESC')
    end

    @pagy, @repositories = pagy_countless(scope)
  end

  def names
    @host = Host.find_by_name!(params[:id])
    scope = @host.repositories
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'last_synced_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('last_synced_at DESC')
    end

    @pagy, @repositories = pagy_countless(scope, max_items: 10000)
    render json: @repositories.pluck(:full_name)
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    if @repository
      render :show
    else
      render json: { error: 'Repository not found' }, status: :not_found
    end
  end

  def lookup
    url = params[:url]
    parsed_url = Addressable::URI.parse(url)
    @host = Host.find_by_domain(parsed_url.host)
    raise ActiveRecord::RecordNotFound unless @host
    path = parsed_url.path.delete_prefix('/').chomp('/')
    @repository = @host.repositories.find_by('lower(full_name) = ?', path.downcase)
    if @repository
      @repository.sync_async unless @repository.last_synced_at.present? && @repository.last_synced_at > 1.day.ago
      render :show
    else
      @host.sync_repository_async(path) if path.present?
      render json: { error: 'Repository not found' }, status: :not_found
    end
  end
end