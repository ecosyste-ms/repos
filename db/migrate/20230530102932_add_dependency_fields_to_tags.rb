class AddDependencyFieldsToTags < ActiveRecord::Migration[7.0]
  def change
    add_column :tags, :dependencies_parsed_at, :datetime
    add_column :tags, :dependency_job_id, :string
  end
end
