class OwnersController < ApplicationController
  def show
    @host = Host.find_by_name!(params[:host_id])
    @owner = params[:id]
    @pagy, @repositories = pagy(@host.repositories.owner(params[:id]))
    raise ActiveRecord::RecordNotFound if @pagy.count.zero?
  end
end