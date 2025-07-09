class CreateImports < ActiveRecord::Migration[8.0]
  def change
    create_table :imports do |t|
      t.string :filename
      t.datetime :imported_at
      t.integer :push_events_count
      t.integer :release_events_count
      t.integer :repositories_synced_count
      t.integer :releases_synced_count
      t.boolean :success
      t.text :error_message

      t.timestamps
    end
    add_index :imports, :filename, unique: true
  end
end
