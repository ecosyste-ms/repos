class AddUsageLastCalculatedToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :usage_last_calculated, :datetime
  end
end
