class AddLastSyncedAtIndexToOwners < ActiveRecord::Migration[7.0]
  def change
    add_index :owners, :last_synced_at
  end
end
