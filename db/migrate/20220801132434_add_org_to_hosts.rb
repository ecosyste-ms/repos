class AddOrgToHosts < ActiveRecord::Migration[7.0]
  def change
    add_column :hosts, :org, :string
  end
end
