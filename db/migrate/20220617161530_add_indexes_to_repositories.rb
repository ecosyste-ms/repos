class AddIndexesToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_index :repositories, 'host_id, lower(full_name)', unique: true
    add_index :repositories, 'host_id, uuid', unique: true
  end
end
