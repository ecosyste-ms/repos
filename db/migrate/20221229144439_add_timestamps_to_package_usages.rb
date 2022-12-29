class AddTimestampsToPackageUsages < ActiveRecord::Migration[7.0]
  def change
    add_column :package_usages, :created_at, :datetime
    add_column :package_usages, :updated_at, :datetime
  end
end
