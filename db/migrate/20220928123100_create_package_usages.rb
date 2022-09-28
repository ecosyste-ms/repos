class CreatePackageUsages < ActiveRecord::Migration[7.0]
  def change
    create_table :package_usages do |t|
      t.string :ecosystem
      t.string :name
      t.bigint :dependents_count, default: 0
      t.integer :repo_ids, array: true, default: []
      t.json :requirements, default: {}
      t.json :kind, default: {}
      t.json :direct, default: {}
    end
  end
end
