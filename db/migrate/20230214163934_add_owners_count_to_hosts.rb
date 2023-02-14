class AddOwnersCountToHosts < ActiveRecord::Migration[7.0]
  def change
    add_column :hosts, :owners_count, :integer, default: 0
  end
end
