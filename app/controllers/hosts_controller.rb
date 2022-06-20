class HostsController < ApplicationController
  def show
    @host = Host.find_by_name(params[:id])
    @pagy, @repositories = pagy_countless(@host.repositories.where.not(last_synced_at:nil).order('last_synced_at desc'))
  end
end