class Api::V1::HostsController < Api::V1::ApplicationController
  def index
    scope = Host.all.order('repositories_count DESC')
    @pagy, @hosts = pagy(scope)
    fresh_when @hosts, public: true
  end

  def show
    @host = Host.find_by_name!(params[:id])
    fresh_when @host, public: true
  end
end