class AddCommitStatsToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :commit_stats, :json
  end
end
