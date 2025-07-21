class AddStatusFieldsToHosts < ActiveRecord::Migration[8.0]
  def change
    add_column :hosts, :status, :string
    add_column :hosts, :status_checked_at, :datetime
    add_column :hosts, :response_time, :integer
    add_column :hosts, :last_error, :text
  end
end
