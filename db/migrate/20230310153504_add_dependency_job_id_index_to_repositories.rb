class AddDependencyJobIdIndexToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_index :repositories, :dependency_job_id
  end
end
