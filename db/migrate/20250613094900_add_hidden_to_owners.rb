class AddHiddenToOwners < ActiveRecord::Migration[8.0]
  def change
    add_column :owners, :hidden, :boolean
  end
end
