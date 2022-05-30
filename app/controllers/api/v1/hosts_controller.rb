class Api::V1::HostsController < Api::V1::ApplicationController
  def index
    @hosts = Host.all
  end

  def show
    @host = Host.find_by_name(params[:id])
  end
end