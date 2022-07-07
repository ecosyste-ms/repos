class AddDependencyJobIdToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :dependency_job_id, :string
  end
end
