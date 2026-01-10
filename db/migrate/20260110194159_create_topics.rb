class CreateTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :topics do |t|
      t.references :host, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.integer :repositories_count, default: 0, null: false
      t.timestamps
    end

    add_index :topics, [:host_id, :name], unique: true
    add_index :topics, :name
    add_index :topics, [:host_id, :repositories_count]
    add_index :topics, :repositories_count
  end
end
