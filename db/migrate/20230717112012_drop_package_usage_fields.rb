class DropPackageUsageFields < ActiveRecord::Migration[7.0]
  def change
    remove_column :package_usages, :repo_ids
    remove_column :package_usages, :requirements
    remove_column :package_usages, :kind
    remove_column :package_usages, :direct
  end
end
