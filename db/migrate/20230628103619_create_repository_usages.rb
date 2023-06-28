class CreateRepositoryUsages < ActiveRecord::Migration[7.0]
  def change
    create_table :repository_usages do |t|
      t.integer :repository_id, index: true
      t.integer :package_usage_id, index: true
    end
  end
end
