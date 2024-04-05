class Api::V1::DependenciesController < Api::V1::ApplicationController
  def index
    @usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    raise ActiveRecord::RecordNotFound unless @usage
    @scope = Dependency.where(ecosystem: @usage.ecosystem, package_name: @usage.name).includes(:manifest, {repository: :host})#.order('dependencies.id asc')
    @scope = @scope.where('dependencies.id > ?', params[:after]) if params[:after].present?
    @pagy, @dependencies = pagy_countless(@scope)
    fresh_when(@dependencies, public: true)
  end
end