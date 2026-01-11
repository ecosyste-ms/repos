class Api::V1::OwnersController < Api::V1::ApplicationController
  before_action :find_host, except: [:ping]

  def index
    scope = @host.owners

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.kind(params[:kind]) if params[:kind].present?
    scope = scope.has_sponsors_listing if params[:has_sponsors_listing].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'last_synced_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('last_synced_at DESC')
    end

    @pagy, @owners = pagy_countless(scope)
    fresh_when @owners, public: true
  end

  def show
    @owner = @host.owners.find_by!('lower(login) = ?', params[:id].downcase)
    raise ActiveRecord::RecordNotFound if @owner.hidden?
    fresh_when @owner, public: true
  end

  def repositories
    max_page = 100
    if params[:page].to_i > max_page
      render json: { error: "Page limit exceeded (max #{max_page})" }, status: :bad_request
      return
    end

    @owner = @host.owners.find_by!('lower(login) = ?', params[:id].downcase)
    raise ActiveRecord::RecordNotFound if @owner.hidden?
    scope = @owner.repositories
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.forked(params[:fork]) if params[:fork].present?
    scope = scope.archived(params[:archived]) if params[:archived].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'last_synced_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('last_synced_at DESC')
    end

    @pagy, @repositories = pagy_countless(scope)
    if stale?(@repositories, public: true)
      render 'api/v1/repositories/index'
    end
  end

  def ping
    PingOwnerWorker.perform_async(params[:host_id], params[:id])
    render json: { message: 'pong' }
  end

  def lookup
    scope = @host.owners

    if params[:name].present?
      scope = scope.where('lower(name) = ?', params[:name].downcase)
    end

    if params[:email].present?
      scope = scope.where('lower(email) = ?', params[:email].downcase)
    end

    @pagy, @owners = pagy_countless(scope)
    fresh_when @owners, public: true
  end

  def sponsors_logins
    @sponsors_logins = @host.owners.has_sponsors_listing.pluck(:login)
    render json: @sponsors_logins
  end

  def names
    scope = @host.owners.visible.order(:id)

    scope = scope.kind(params[:kind]) if params[:kind].present?

    @pagy, @owners = pagy_countless(scope.select(:login), limit_max: 10000)

    expires_in 1.day, public: true
    render json: @owners.pluck(:login)
  end
end
