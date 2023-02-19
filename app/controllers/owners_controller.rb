class OwnersController < ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    @pagy, @owners = pagy_countless(@host.owners.order('repositories_count DESC'))
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @owner = params[:id]
    @owner_record = @host.owners.find_by('lower(login) = ?', @owner.downcase)

    scope = @host.repositories.owner(@owner)
    sort = params[:sort].presence || 'updated_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)
    raise ActiveRecord::RecordNotFound if @repositories.length.zero?
  end

  def subgroup
    @host = Host.find_by_name!(params[:host_id])
    parts = "#{params[:id]}/#{params[:subgroup]}".split('/')
    @owner = parts[0]
    @subgroups = parts[1..-1]

    @pagy, @repositories = pagy_countless(@host.repositories.subgroup(@owner, @subgroups.join('/')))
    raise ActiveRecord::RecordNotFound if @repositories.length.zero?
  end
end