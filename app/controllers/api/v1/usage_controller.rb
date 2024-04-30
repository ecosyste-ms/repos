class Api::V1::UsageController < Api::V1::ApplicationController
  def index
    @ecosystems = PackageUsage.group(:ecosystem).count.sort_by{|e,c| -c }
    fresh_when @ecosystems, public: true
  end

  def ecosystem
    @ecosystem = params[:ecosystem]
    @scope = PackageUsage.where(ecosystem: @ecosystem).order('dependents_count DESC')
    @pagy, @package_usages = pagy_countless(@scope)
    fresh_when @package_usages, public: true
  end

  def show
    @usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    fresh_when @usage, public: true
    if @usage.nil?
      if Dependency.where(ecosystem: params[:ecosystem], package_name: params[:name]).any?
        @usage = PackageUsage.create({
          ecosystem: params[:ecosystem],
          name: params[:name],
          key: "#{params[:ecosystem]}:#{params[:name]}",
          dependents_count: 1})
        @usage.sync
      else
        raise ActiveRecord::RecordNotFound
      end
    end
  end

  def dependent_repositories
    @usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])

    scope = @usage.repositories.includes(:host)

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'id'
      order = params[:order] || 'asc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope#.order('last_synced_at DESC')
    end

    if params[:after_id].present?
      scope = scope.where('repositories.id > ?', params[:after_id])
    end

    scope = scope.forked(params[:fork]) if params[:fork].present?
    scope = scope.archived(params[:archived]) if params[:archived].present?
    scope = scope.starred if params[:starred].present?

    if @usage.nil?
      if Dependency.where(ecosystem: params[:ecosystem], package_name: params[:name]).any?
        @usage = PackageUsage.create({
          ecosystem: params[:ecosystem],
          name: params[:name],
          key: "#{params[:ecosystem]}:#{params[:name]}",
          dependents_count: 1})
        @usage.sync
      else
        raise ActiveRecord::RecordNotFound
      end
    end

    @pagy, @repositories = pagy_countless(scope)
    fresh_when @repositories, public: true
  end

  def ping
    @usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    if @usage
      @usage.sync_async
    else
      if Dependency.where(ecosystem: params[:ecosystem], package_name: params[:name]).any?
        @usage = PackageUsage.create({
          ecosystem: params[:ecosystem],
          name: params[:name],
          key: "#{params[:ecosystem]}:#{params[:name]}",
          dependents_count: 1})
        @usage.sync_async
      end
    end
    render json: { message: 'pong' }
  end
end