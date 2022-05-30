class CreateRepositories < ActiveRecord::Migration[7.0]
  def change
    create_table :repositories do |t|
      t.integer :host_id
      t.string :uuid
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
      t.string :homepage
      t.string :language
      t.boolean :has_issues
      t.boolean :has_wiki
      t.boolean :has_pages
      t.string :mirror_url
      t.string :source_name
      t.string :license
      t.boolean :private
      t.string :status
      t.string :scm
      t.string :pull_requests_enabled
      t.string :logo_url

      t.json :metadata, default: {}

      t.timestamps
    end
  end
end
