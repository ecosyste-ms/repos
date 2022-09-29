class AddUsageUpdatedAtToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :usage_updated_at, :datetime
  end
end
