class AddCompositeIndexToReleases < ActiveRecord::Migration[8.1]
  def up
    execute "SET statement_timeout = 0"
    add_index :releases, [:repository_id, :published_at], order: { published_at: "DESC NULLS LAST" }, name: "index_releases_on_repository_id_and_published_at"
    remove_index :releases, name: "index_releases_on_repository_id"
  end

  def down
    execute "SET statement_timeout = 0"
    add_index :releases, :repository_id, name: "index_releases_on_repository_id"
    remove_index :releases, name: "index_releases_on_repository_id_and_published_at"
  end
end
