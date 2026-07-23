require 'test_helper'

class RepositoryInactiveSyncTest < ActiveSupport::TestCase
  setup do
    REDIS.del(Repository::INACTIVE_SYNC_CURSOR_KEY)
    REDIS.del(Repository::INACTIVE_SYNC_END_ID_KEY)
    SyncInactiveRepositoryWorker.clear
  end

  teardown do
    REDIS.del(Repository::INACTIVE_SYNC_CURSOR_KEY)
    REDIS.del(Repository::INACTIVE_SYNC_END_ID_KEY)
    SyncInactiveRepositoryWorker.clear
  end

  test 'enqueues the next primary key batch and advances the cursor' do
    repositories = create_list(:repository, 3).sort_by(&:id)

    assert_equal 2, Repository.enqueue_inactive_sync_batch(batch_size: 2)
    assert_equal repositories.first(2).map { |repository| [repository.id] }, queued_arguments
    assert_equal repositories.second.id.to_s, REDIS.get(Repository::INACTIVE_SYNC_CURSOR_KEY)
    assert_equal repositories.last.id.to_s, REDIS.get(Repository::INACTIVE_SYNC_END_ID_KEY)
  end

  test 'keeps the endpoint fixed until the sweep finishes' do
    repositories = create_list(:repository, 2).sort_by(&:id)

    Repository.enqueue_inactive_sync_batch(batch_size: 1)
    later_repository = create(:repository)
    SyncInactiveRepositoryWorker.clear

    assert_equal 1, Repository.enqueue_inactive_sync_batch(batch_size: 10)
    assert_equal [[repositories.last.id]], queued_arguments
    refute_includes queued_arguments, [later_repository.id]
  end

  test 'resets the cursor after reaching the endpoint' do
    repository = create(:repository)

    Repository.enqueue_inactive_sync_batch(batch_size: 1)
    SyncInactiveRepositoryWorker.clear

    assert_equal 0, Repository.enqueue_inactive_sync_batch(batch_size: 1)
    assert_nil REDIS.get(Repository::INACTIVE_SYNC_CURSOR_KEY)
    assert_nil REDIS.get(Repository::INACTIVE_SYNC_END_ID_KEY)
    assert_equal repository.id, Repository.maximum(:id)
  end

  def queued_arguments
    SyncInactiveRepositoryWorker.jobs.map { |job| job['args'] }
  end
end
