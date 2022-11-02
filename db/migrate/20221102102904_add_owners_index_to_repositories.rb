class AddOwnersIndexToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_index :repositories, :owner
  end
end
