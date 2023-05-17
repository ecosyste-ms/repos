class AddPreviousNamesToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :previous_names, :string, array: true, default: []
    add_index :repositories, :previous_names, using: 'gin'
  end
end
