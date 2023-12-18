class AddLatestTagDetailsToRepositories < ActiveRecord::Migration[7.1]
  def change
    add_column :repositories, :latest_tag_name, :string
    add_column :repositories, :latest_tag_published_at, :datetime
  end
end
