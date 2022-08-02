class ChangePullRequestsEnabledToBoolean < ActiveRecord::Migration[7.0]
  def change
    change_column :repositories, :pull_requests_enabled, "boolean USING pull_requests_enabled::boolean"
  end
end
