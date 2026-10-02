class AddHostCreatedAtIndexToOwners < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    without_statement_timeout do
      add_index :owners, [:host_id, :created_at], algorithm: :concurrently
    end
  end

  def down
    without_statement_timeout do
      remove_index :owners, [:host_id, :created_at], algorithm: :concurrently
    end
  end

  def without_statement_timeout
    previous_timeout = connection.select_value('SHOW statement_timeout')
    execute 'SET statement_timeout = 0'
    yield
  ensure
    execute "SET statement_timeout = #{connection.quote(previous_timeout)}" if previous_timeout
  end
end
