class AddDependenciesParsedAtToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :dependencies_parsed_at, :datetime
    add_index :repositories, :dependencies_parsed_at
  end
end
