class Api::V1::RepositoriesController < Api::V1::ApplicationController
  before_action :find_host, only: [:index, :show, :sbom, :ping]
  before_action :find_host_by_id, only: [:names]

  def index
    max_page = 100
    if params[:page].to_i > max_page
      render json: { error: "Page limit exceeded (max #{max_page})" }, status: :bad_request
      return
    end

    scope = @host.repositories
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.forked(params[:fork]) if params[:fork].present?
    scope = scope.archived(params[:archived]) if params[:archived].present?

    sort = params[:sort] || 'id'
    order = params[:order] || 'desc'
    sort_options = sort.split(',').zip(order.split(',')).to_h
    scope = scope.order(sort_options)

    @pagy, @repositories = pagy_countless(scope)
    fresh_when @repositories, public: true
  end

  def names
    max_page = 100
    if params[:page].to_i > max_page
      render json: { error: "Page limit exceeded (max #{max_page})" }, status: :bad_request
      return
    end

    scope = @host.repositories
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.forked(params[:fork]) if params[:fork].present?
    scope = scope.archived(params[:archived]) if params[:archived].present?

    sort = params[:sort] || 'id'
    order = params[:order] || 'desc'
    sort_options = sort.split(',').zip(order.split(',')).to_h
    scope = scope.order(sort_options)

    @pagy, @repositories = pagy_countless(scope, limit_max: 10000)
    if stale?(@repositories, public: true)
      render json: @repositories.pluck(:full_name)
    end
  end

  def show
    @repository = @host.find_repository(params[:id].downcase)
    if @repository
      render json: { error: 'Repository not found' }, status: :not_found and return if @repository.owner_hidden?
      if stale?(@repository, public: true)
        unless @repository.full_name.downcase == params[:id].downcase
          redirect_to api_v1_host_repository_path(@host, @repository.full_name), status: :moved_permanently
          return
        end
        render :show
      end
    else
      render json: { error: 'Repository not found' }, status: :not_found
    end
  end

  def sbom
    @repository = @host.find_repository(params[:id].downcase)
    if @repository
      render json: { error: 'Repository not found' }, status: :not_found and return if @repository.owner_hidden?
      if stale?(@repository, public: true)
        render json: @repository.sbom, status: :ok
      end
    else
      render json: { error: 'Repository not found' }, status: :not_found
    end
  end

  def lookup
    if params[:url].present?
      url = params[:url]
      parsed_url = Addressable::URI.parse(url)
      @host = Host.find_by_domain(parsed_url.host)
      raise ActiveRecord::RecordNotFound unless @host
      path = parsed_url.path.delete_prefix('/').chomp('/')
      @repository = @host.find_repository(path.downcase)
    elsif params[:purl].present?
      begin
        purl = PackageURL.parse(params[:purl])
        if purl.qualifiers.present? && purl.qualifiers['repository_url'].present?
          @host = Host.find_by_url(purl.qualifiers['repository_url'])
        else
          @host = Host.kind(purl.type).first # TODO gitlab and codeberg defaults 
        end
        raise ActiveRecord::RecordNotFound unless @host
        path = [purl.namespace, purl.name].compact.join('/')
        @repository = @host.find_repository(path.downcase)
      rescue => e
        raise ActiveRecord::RecordNotFound
      end
    end
    if @repository
      render json: { error: 'Repository not found' }, status: :not_found and return if @repository.owner_hidden?
      force = params[:force].present?
      if force
        @repository.sync_async(true)
      else
        @repository.sync_async unless @repository.last_synced_at.present? && @repository.last_synced_at > 1.hour.ago
      end
      render :show if stale?(@repository, public: true)
    else
      @host.sync_repository_async(path) if path.present?
      render json: { error: 'Repository not found' }, status: :not_found
    end
  end

  def ping
    PingWorker.perform_async(params[:host_id], params[:id], params[:force].present?)
    render json: { message: 'pong' }
  end
end