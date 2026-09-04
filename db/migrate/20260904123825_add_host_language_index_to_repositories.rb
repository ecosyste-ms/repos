class AddHostLanguageIndexToRepositories < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :repositories,
              [:host_id, :language],
              where: "fork = false",
              algorithm: :concurrently,
              name: "index_repositories_on_host_language_nonfork"
  end
end
