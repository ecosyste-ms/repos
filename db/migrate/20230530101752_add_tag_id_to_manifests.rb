class AddTagIdToManifests < ActiveRecord::Migration[7.0]
  def change
    add_column :manifests, :tag_id, :integer
    add_index :manifests, :tag_id
  end
end
