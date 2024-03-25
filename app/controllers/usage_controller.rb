class UsageController < ApplicationController
  def index
    @ecosystems = PackageUsage.group(:ecosystem).count.sort_by{|e,c| -c }
    expires_in 1.day, public: true
  end

  def ecosystem
    @ecosystem = params[:ecosystem]
    @scope = PackageUsage.where(ecosystem: @ecosystem).select('ecosystem,name,dependents_count,package').order('dependents_count DESC')
    @pagy, @package_usages = pagy_countless(@scope)
    expires_in 1.day, public: true
  end

  def show
    @package_usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    fresh_when @package_usage, public: true
    if @package_usage.nil?
      if Dependency.where(ecosystem: params[:ecosystem], package_name: params[:name]).any?
        @package_usage = PackageUsage.create({
          ecosystem: params[:ecosystem],
          name: params[:name],
          key: "#{params[:ecosystem]}:#{params[:name]}",
          dependents_count: 1})
        @package_usage.sync
      else
        raise ActiveRecord::RecordNotFound
      end
    end
    @scope = Dependency.where(ecosystem: @package_usage.ecosystem, package_name: @package_usage.name).includes(:manifest, {repository: :host})
    @pagy, @dependencies = pagy_countless(@scope)
  end
end
