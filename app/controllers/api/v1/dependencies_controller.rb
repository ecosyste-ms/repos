class Api::V1::DependenciesController < Api::V1::ApplicationController
  def index
    @usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    raise ActiveRecord::RecordNotFound unless @usage
    @scope = Dependency.where(ecosystem: @usage.ecosystem, package_name: @usage.name).includes(:repository, :manifest).order('id asc')
    @scope = @scope.where('id > ?', params[:after]) if params[:after].present?
    @pagy, @dependencies = pagy(@scope)
    fresh_when(@dependencies, public: true)
  end
end