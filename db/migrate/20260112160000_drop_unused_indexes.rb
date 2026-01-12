class DropUnusedIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    remove_index :dependencies, name: :index_dependencies_on_package_name_and_ecosystem, algorithm: :concurrently, if_exists: true
    remove_index :repositories, name: :index_repositories_on_last_synced_at, algorithm: :concurrently, if_exists: true
    remove_index :repositories, name: :index_repositories_on_previous_names, algorithm: :concurrently, if_exists: true
    remove_index :repositories, name: :index_repositories_on_dependency_job_id, algorithm: :concurrently, if_exists: true
    remove_index :repositories, name: :index_repositories_on_dependencies_parsed_at, algorithm: :concurrently, if_exists: true
    remove_index :repositories, name: :index_repositories_on_topics, algorithm: :concurrently, if_exists: true
    remove_index :owners, name: :index_owners_on_last_synced_at, algorithm: :concurrently, if_exists: true
    remove_index :package_usages, name: :index_package_usages_on_package_last_synced_at, algorithm: :concurrently, if_exists: true
  end
end
