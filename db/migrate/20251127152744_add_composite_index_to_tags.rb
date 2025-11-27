class AddCompositeIndexToTags < ActiveRecord::Migration[8.1]
  def up
    execute "SET statement_timeout = 0"
    add_index :tags, [:repository_id, :published_at], order: { published_at: "DESC NULLS LAST" }, name: "index_tags_on_repository_id_and_published_at"
    remove_index :tags, name: "index_tags_on_repository_id"
  end

  def down
    execute "SET statement_timeout = 0"
    add_index :tags, :repository_id, name: "index_tags_on_repository_id"
    remove_index :tags, name: "index_tags_on_repository_id_and_published_at"
  end
end
