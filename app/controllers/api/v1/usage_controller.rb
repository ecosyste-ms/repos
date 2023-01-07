class Api::V1::UsageController < Api::V1::ApplicationController
  def index
    @ecosystems = PackageUsage.group(:ecosystem).count.sort_by{|e,c| -c }
  end

  def ecosystem
    @ecosystem = params[:ecosystem]
    @scope = PackageUsage.where(ecosystem: @ecosystem).order('dependents_count DESC')
    @pagy, @package_usages = pagy(@scope)
  end

  def show
    @usage = PackageUsage.find_by!(ecosystem: params[:ecosystem], name: params[:name])
  end
end