class AddTagsLastSyncedAtToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :tags_last_synced_at, :datetime
  end
end
