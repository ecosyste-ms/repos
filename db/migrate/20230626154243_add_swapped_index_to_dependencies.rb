class AddSwappedIndexToDependencies < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!
  
  def change
    add_index :dependencies, [:package_name, :ecosystem], algorithm: :concurrently
  end
end
