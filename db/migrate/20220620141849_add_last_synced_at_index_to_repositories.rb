class AddLastSyncedAtIndexToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_index :repositories, :last_synced_at
  end
end
