class AddFilesChangedToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :files_changed, :boolean
  end
end
