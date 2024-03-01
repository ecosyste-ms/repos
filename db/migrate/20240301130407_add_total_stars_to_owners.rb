class AddTotalStarsToOwners < ActiveRecord::Migration[7.1]
  def change
    add_column :owners, :total_stars, :bigint
  end
end
