class AddKeyToPackageUsages < ActiveRecord::Migration[7.0]
  def change
    add_column :package_usages, :key, :string
    add_index :package_usages, :key, unique: true
  end
end
