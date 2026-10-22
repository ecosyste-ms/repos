class AddIndexToReleasesTagId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Created by hand in production: building it on releases outlasts the release task's statement timeout.
  def up
    add_index :releases, :tag_id, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :releases, :tag_id, algorithm: :concurrently, if_exists: true
  end
end
