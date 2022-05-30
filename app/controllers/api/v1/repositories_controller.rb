class Api::V1::RepositoriesController < Api::V1::ApplicationController
  def index
    @host = Host.find_by_name(params[:host_id])
    @pagy, @repositories = pagy(@host.repositories)
  end

  def show
    @host = Host.find_by_name(params[:host_id])
    @repository = @host.repositories.find_by_full_name(params[:id])
  end
end