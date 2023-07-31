class Api::V1::OwnersController < Api::V1::ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    scope = @host.owners
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

    @pagy, @owners = pagy_countless(scope)
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @owner = @host.owners.find_by!('lower(login) = ?', params[:id].downcase)
  end

  def repositories
    @host = Host.find_by_name!(params[:host_id])
    @owner = @host.owners.find_by!('lower(login) = ?', params[:id].downcase)
    scope = @owner.repositories
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
    render 'api/v1/repositories/index'
  end

  def ping
    PingOwnerWorker.perform_async(params[:host_id], params[:id])
    render json: { message: 'pong' }
  end

  def lookup
    @host = Host.find_by_name!(params[:host_id])
    scope = @host.owners
    
    if params[:name].present?
      scope = scope.where('lower(name) = ?', params[:name].downcase)
    end

    if params[:email].present?
      scope = scope.where('lower(email) = ?', params[:email].downcase)
    end

    @pagy, @owners = pagy_countless(scope)
  end
end
