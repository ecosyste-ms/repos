class AddVersionToHosts < ActiveRecord::Migration[7.1]
  def change
    add_column :hosts, :version, :string
  end
end
