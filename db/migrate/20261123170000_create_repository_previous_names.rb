class CreateRepositoryPreviousNames < ActiveRecord::Migration[8.1]
  def change
    create_table :repository_previous_names do |t|
      t.bigint :host_id, null: false
      t.bigint :repository_id, null: false
      t.string :full_name, null: false
      t.timestamps
    end

    add_index :repository_previous_names, [:host_id, :full_name], unique: true
    add_index :repository_previous_names, :repository_id
  end
end
