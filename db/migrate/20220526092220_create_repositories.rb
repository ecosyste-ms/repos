class CreateRepositories < ActiveRecord::Migration[7.0]
  def change
    create_table :repositories do |t|
      t.integer :host_id
      t.integer :remote_id
      t.string :full_name
      t.string :owner
      t.string :main_language
      t.boolean :archived
      t.boolean :fork
      t.string :description
      t.datetime :pushed_at
      t.integer :size
      t.integer :stargazers_count
      t.integer :open_issues_count
      t.integer :forks_count
      t.integer :subscribers_count
      t.string :default_branch
      t.datetime :last_synced_at
      t.string :etag
      t.string :topics, default: [], array: true
      t.string :latest_commit_sha
      t.json :metadata, default: {}

      t.timestamps
    end
  end
end
