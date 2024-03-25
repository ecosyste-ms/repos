class AddFollowerCountsToOwners < ActiveRecord::Migration[7.1]
  def change
    add_column :owners, :followers, :integer
    add_column :owners, :following, :integer
  end
end
