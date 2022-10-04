class AddPackageToPackageUsages < ActiveRecord::Migration[7.0]
  def change
    add_column :package_usages, :package, :json, default: {}
    add_column :package_usages, :package_last_synced_at, :datetime
  end
end
