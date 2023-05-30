class AddTagsCountToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :tags_count, :integer
  end
end
