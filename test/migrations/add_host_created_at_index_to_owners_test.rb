require 'test_helper'
require Rails.root.join('db/migrate/20261002180000_add_host_created_at_index_to_owners')

class AddHostCreatedAtIndexToOwnersTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @migration = AddHostCreatedAtIndexToOwners.new
    @connection = ActiveRecord::Base.connection
    @previous_timeout = @connection.select_value('SHOW statement_timeout')
    @connection.execute("SET statement_timeout = '17s'")
  end

  teardown do
    @migration.migrate(:up) unless @connection.index_exists?(:owners, [:host_id, :created_at])
    @connection.execute("SET statement_timeout = #{@connection.quote(@previous_timeout)}")
  end

  test 'builds and removes the index concurrently with the timeout disabled' do
    statements = []
    callback = lambda do |*, payload|
      next unless payload[:sql].match?(/(?:CREATE|DROP) INDEX/i)

      statements << payload[:sql]
      assert_equal '0', @connection.select_value('SHOW statement_timeout')
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      @migration.migrate(:down)
      assert_not @connection.index_exists?(:owners, [:host_id, :created_at])
      assert_equal '17s', @connection.select_value('SHOW statement_timeout')

      @migration.migrate(:up)
      assert @connection.index_exists?(:owners, [:host_id, :created_at], valid: true)
      assert_equal '17s', @connection.select_value('SHOW statement_timeout')
    end

    assert_equal 2, statements.size
    assert_match(/DROP INDEX CONCURRENTLY/i, statements.first)
    assert_match(/CREATE INDEX CONCURRENTLY/i, statements.last)
  end

  test 'restores the timeout when index creation fails' do
    assert_raises(ActiveRecord::StatementInvalid) { @migration.migrate(:up) }

    assert_equal '17s', @connection.select_value('SHOW statement_timeout')
  end
end
