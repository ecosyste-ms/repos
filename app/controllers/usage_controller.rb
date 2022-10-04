class UsageController < ApplicationController
  def index
    @ecosystems = PackageUsage.group(:ecosystem).count.sort_by{|e,c| -c }
  end

  def ecosystem
    @ecosystem = params[:ecosystem]
    @scope = PackageUsage.where(ecosystem: @ecosystem).select('ecosystem,name,dependents_count,package').order('dependents_count DESC')
    @pagy, @package_usages = pagy(@scope)
  end

  def show
    @package_usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    raise ActiveRecord::RecordNotFound unless @package_usage
    @scope = @package_usage.dependent_repos
    @pagy, @repositories = pagy(@scope)
  end
end
