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
    @owner = @host.owners.find_by('lower(login) = ?', params[:id].downcase)
  end
end
