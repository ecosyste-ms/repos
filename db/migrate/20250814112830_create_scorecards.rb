class CreateScorecards < ActiveRecord::Migration[8.0]
  def change
    create_table :scorecards do |t|
      t.json :data
      t.datetime :last_synced_at
      t.references :repository, null: false, foreign_key: true

      t.timestamps
    end
  end
end
