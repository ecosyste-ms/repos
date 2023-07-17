class AddRepositoryUsagesCountToPackageUsages < ActiveRecord::Migration[7.0]
  def change
    add_column :package_usages, :repository_usages_count, :integer
  end
end
