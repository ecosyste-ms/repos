class OwnersController < ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    @pagy, @owners = pagy_countless(@host.owners)
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @owner = params[:id]
    @pagy, @repositories = pagy_countless(@host.repositories.owner(@owner))
    raise ActiveRecord::RecordNotFound if @pagy.count.zero?
  end

  def subgroup
    @host = Host.find_by_name!(params[:host_id])
    parts = "#{params[:id]}/#{params[:subgroup]}".split('/')
    @owner = parts[0]
    @subgroups = parts[1..-1]

    @pagy, @repositories = pagy_countless(@host.repositories.subgroup(@owner, @subgroups.join('/')))
    raise ActiveRecord::RecordNotFound if @pagy.count.zero?
  end
end