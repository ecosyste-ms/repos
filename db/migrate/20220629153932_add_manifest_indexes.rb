class AddManifestIndexes < ActiveRecord::Migration[7.0]
  def change
    add_index :manifests, :repository_id
    add_index :dependencies, :manifest_id
  end
end
