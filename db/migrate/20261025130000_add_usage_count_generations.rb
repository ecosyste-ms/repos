class AddUsageCountGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :repositories, :usage_count_generation, :bigint
    add_column :package_usages, :usage_count_generation, :bigint
  end
end
