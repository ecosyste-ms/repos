class CreateDependencies < ActiveRecord::Migration[7.0]
  def change
    create_table :dependencies do |t|
      t.integer :manifest_id
      t.integer :repository_id
      t.boolean :optional, default: false
      t.string :package_name
      t.string :ecosystem
      t.string :requirements
      t.string :kind
      t.boolean :direct, default: false

      t.timestamps
    end
  end
end
