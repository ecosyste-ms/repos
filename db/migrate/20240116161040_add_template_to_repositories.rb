class AddTemplateToRepositories < ActiveRecord::Migration[7.1]
  def change
    add_column :repositories, :template, :boolean
    add_column :repositories, :template_full_name, :string
  end
end
