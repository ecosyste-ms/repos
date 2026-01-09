class Api::V1::UsageController < Api::V1::ApplicationController
  def index
    @ecosystems = PackageUsage.group(:ecosystem).count.sort_by{|e,c| -c }
    expires_in 1.week, public: true
  end

  def ecosystem
    @ecosystem = params[:ecosystem]
    @scope = PackageUsage.where(ecosystem: @ecosystem).order('dependents_count DESC')
    @pagy, @package_usages = pagy_countless(@scope)
    fresh_when @package_usages, public: true
  end

  def show
    @usage = find_or_create_usage!
    fresh_when @usage, public: true
  end

  def dependent_repositories
    @usage = find_or_create_usage!

    scope = @usage.repositories.includes(:host)

    sort = params[:sort] || 'id'
    order = params[:order] || 'asc'
    sort_options = sort.split(',').zip(order.split(',')).to_h
    scope = scope.order(sort_options)

    if params[:after_id].present?
      scope = scope.where('repositories.id > ?', params[:after_id])
    end

    scope = scope.forked(params[:fork]) if params[:fork].present?
    scope = scope.archived(params[:archived]) if params[:archived].present?
    scope = scope.starred if params[:starred].present?
    scope = scope.minimum_stars(params[:min_stars]) if params[:min_stars].present?

    @pagy, @repositories = pagy_countless(scope)
    fresh_when @repositories, public: true
  end

  def ping
    @usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    if @usage
      @usage.sync_async
    else
      @usage = create_usage_if_dependency_exists
      @usage&.sync_async
    end
    render json: { message: 'pong' }
  end

  def find_or_create_usage!
    usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    return usage if usage

    usage = create_usage_if_dependency_exists
    raise ActiveRecord::RecordNotFound unless usage
    usage.sync
    usage
  end

  def create_usage_if_dependency_exists
    return nil unless Dependency.where(ecosystem: params[:ecosystem], package_name: params[:name]).exists?

    PackageUsage.create(
      ecosystem: params[:ecosystem],
      name: params[:name],
      key: "#{params[:ecosystem]}:#{params[:name]}",
      dependents_count: 1
    )
  end
end