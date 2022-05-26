class CreateHosts < ActiveRecord::Migration[7.0]
  def change
    create_table :hosts do |t|
      t.string :name
      t.string :url
      t.string :kind
      t.integer :repositories_count, default: 0

      t.timestamps
    end
  end
end
