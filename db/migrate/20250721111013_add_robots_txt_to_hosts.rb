class AddRobotsTxtToHosts < ActiveRecord::Migration[8.0]
  def change
    add_column :hosts, :robots_txt_content, :text
    add_column :hosts, :robots_txt_updated_at, :datetime
    add_column :hosts, :robots_txt_status, :string
  end
end
