class CreateTags < ActiveRecord::Migration[7.0]
  def change
    create_table :tags do |t|
      t.integer :repository_id
      t.string :name
      t.string :sha
      t.string :kind
      t.datetime :published_at

      t.timestamps
    end
  end
end
