class HostsController < ApplicationController
  def show
    @host = Host.find_by_name(params[:id])
    @pagy, @repositories = pagy(@host.repositories)
  end
end