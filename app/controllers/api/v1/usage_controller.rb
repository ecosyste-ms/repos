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
    @usage = PackageUsage.find_by(ecosystem: params[:ecosystem], name: params[:name])
    if @usage.nil?
      if Dependency.where(ecosystem: params[:ecosystem], package_name: params[:name]).any?
        @usage = PackageUsage.create({
          ecosystem: params[:ecosystem],
          name: params[:name],
          dependents_count: 1})
        @usage.sync
        @usage.sync_repository if @usage.package
      else
        raise ActiveRecord::RecordNotFound
      end
    end
  end
end