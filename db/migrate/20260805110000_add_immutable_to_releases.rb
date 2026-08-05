class AddImmutableToReleases < ActiveRecord::Migration[8.1]
  def change
    add_column :releases, :immutable, :boolean
  end
end
