class CreateReleases < ActiveRecord::Migration[7.0]
  def change
    create_table :releases do |t|
      t.integer :repository_id, index: true, foreign_key: true, null: false
      t.string :uuid
      t.string :tag_name
      t.string :target_commitish
      t.integer :tag_id
      t.string :name
      t.text :body
      t.boolean :draft
      t.boolean :prerelease
      t.datetime :published_at
      t.string :author
      t.json :assets, default: []
      t.datetime :last_synced_at

      t.timestamps
    end
  end
end
