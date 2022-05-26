class CreateManifests < ActiveRecord::Migration[7.0]
  def change
    create_table :manifests do |t|
      t.integer :repository_id
      t.string :ecosystem
      t.string :filepath
      t.string :sha
      t.string :branch
      t.string :kind

      t.timestamps
    end
  end
end
