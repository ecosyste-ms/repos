class UsageController < ApplicationController
  MAX_PAGES = 100

  def index
    @ecosystems = PackageUsage.ecosystem_counts
    expires_in 1.day, public: true
  end

  def ecosystem
    @ecosystem = params[:ecosystem]
    @scope = PackageUsage.where(ecosystem: @ecosystem).select('ecosystem,name,dependents_count,package').order('dependents_count DESC')
    @pagy, @package_usages = pagy_countless(@scope, max_pages: MAX_PAGES)
    expires_in 1.day, public: true
  end

  def show
    @package_usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    raise ActiveRecord::RecordNotFound if @package_usage.nil?
    @scope = Dependency.where(ecosystem: @package_usage.ecosystem, package_name: @package_usage.name).includes(:manifest, {repository: :host})
    @pagy, @dependencies = pagy_countless(@scope, max_pages: MAX_PAGES)
    fresh_when @package_usage, public: true
  end
end
