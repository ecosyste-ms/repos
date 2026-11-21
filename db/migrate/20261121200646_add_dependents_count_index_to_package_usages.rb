class AddDependentsCountIndexToPackageUsages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Created by hand in production: building it on 7.9M rows outlasts the release task's statement timeout.
  def up
    add_index :package_usages, [:ecosystem, :dependents_count], order: { dependents_count: :desc }, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :package_usages, [:ecosystem, :dependents_count], algorithm: :concurrently, if_exists: true
  end
end
