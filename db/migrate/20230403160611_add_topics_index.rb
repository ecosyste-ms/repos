class AddTopicsIndex < ActiveRecord::Migration[7.0]
  def change
    add_index :repositories, :topics, using: :gin
  end
end
