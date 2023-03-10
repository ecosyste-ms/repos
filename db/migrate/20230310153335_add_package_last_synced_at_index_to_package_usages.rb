class AddPackageLastSyncedAtIndexToPackageUsages < ActiveRecord::Migration[7.0]
  def change
    add_index :package_usages, :package_last_synced_at
  end
end
