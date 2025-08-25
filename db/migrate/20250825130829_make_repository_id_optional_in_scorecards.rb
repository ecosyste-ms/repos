class MakeRepositoryIdOptionalInScorecards < ActiveRecord::Migration[8.0]
  def change
    change_column_null :scorecards, :repository_id, true
  end
end
