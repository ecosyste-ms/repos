class OwnersController < ApplicationController
  def show
    @host = Host.find_by_name!(params[:host_id])
    @owner = params[:id]
    @pagy, @repositories = pagy(@host.repositories.owner(params[:id]).where.not(last_synced_at:nil).order('last_synced_at desc'))
  end
end