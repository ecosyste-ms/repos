class AddEcosystemNameIndexToPackageUsages < ActiveRecord::Migration[7.0]
  def change
    add_index :package_usages, [:ecosystem, :name]
  end
end
