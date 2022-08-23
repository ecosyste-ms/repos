class AddRepositoryIndexToTags < ActiveRecord::Migration[7.0]
  def change
    add_index :tags, :repository_id
  end
end
