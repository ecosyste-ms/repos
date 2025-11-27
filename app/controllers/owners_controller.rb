class OwnersController < ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    scope = @host.owners.order('repositories_count DESC')
    scope = scope.has_sponsors_listing if params[:has_sponsors_listing].present?
    @pagy, @owners = pagy_countless(scope)
    expires_in 1.day, public: true
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @owner = params[:id]
    @owner_record = @host.owners.find_by('lower(login) = ?', @owner.downcase)
    raise ActiveRecord::RecordNotFound if @owner_record&.hidden?
    fresh_when(@owner_record, public: true)
    scope = @host.repositories.owner(@owner).includes(:host)
    
    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'updated_at'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('updated_at desc')
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