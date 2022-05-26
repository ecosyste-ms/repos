class HostsController < ApplicationController
  def show
    @host = Host.find_by_name(params[:id])
  end
end