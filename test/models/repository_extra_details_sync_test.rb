require 'test_helper'

class RepositoryExtraDetailsSyncTest < ActiveSupport::TestCase
  setup do
    @unique_jobs_enabled = SidekiqUniqueJobs.config.enabled
    SidekiqUniqueJobs.config.enabled = false
    REDIS.del(Repository::EXTRA_DETAILS_CURSOR_KEY, Repository::EXTRA_DETAILS_END_ID_KEY)
    SyncExtraDetailsWorker.clear
  end

  teardown do
    REDIS.del(Repository::EXTRA_DETAILS_CURSOR_KEY, Repository::EXTRA_DETAILS_END_ID_KEY)
    SyncExtraDetailsWorker.clear
    SidekiqUniqueJobs.config.enabled = @unique_jobs_enabled
  end

  test 'enqueues pending repositories in the next id range and advances the cursor' do
    pending = create(:repository, files_changed: true)
    create(:repository, files_changed: false)
    create(:repository, files_changed: true, fork: true)
    beyond_batch = create(:repository, files_changed: true)

    assert_equal 1, Repository.sync_extra_details_async(batch_size: beyond_batch.id - pending.id)

    assert_equal [[pending.id]], queued_arguments
    assert_equal (beyond_batch.id - 1).to_s, REDIS.get(Repository::EXTRA_DETAILS_CURSOR_KEY)
    assert_equal beyond_batch.id.to_s, REDIS.get(Repository::EXTRA_DETAILS_END_ID_KEY)
  end

  test 'advances past ranges with nothing pending' do
    idle = create(:repository, files_changed: false)
    pending = create(:repository, files_changed: true)

    assert_equal 0, Repository.sync_extra_details_async(batch_size: idle.id)
    assert_equal 1, Repository.sync_extra_details_async(batch_size: pending.id - idle.id)
    assert_equal [[pending.id]], queued_arguments
  end

  test 'keeps the endpoint fixed until the sweep finishes' do
    first = create(:repository, files_changed: true)
    last = create(:repository, files_changed: true)

    Repository.sync_extra_details_async(batch_size: first.id)
    later = create(:repository, files_changed: true)
    SyncExtraDetailsWorker.clear

    assert_equal 1, Repository.sync_extra_details_async(batch_size: later.id)
    assert_equal [[last.id]], queued_arguments
  end

  test 'resets the cursor after reaching the endpoint' do
    create(:repository, files_changed: true)

    Repository.sync_extra_details_async
    SyncExtraDetailsWorker.clear

    assert_equal 0, Repository.sync_extra_details_async
    assert_empty queued_arguments
    assert_nil REDIS.get(Repository::EXTRA_DETAILS_CURSOR_KEY)
    assert_nil REDIS.get(Repository::EXTRA_DETAILS_END_ID_KEY)
  end

  def queued_arguments
    SyncExtraDetailsWorker.jobs.map { |job| job['args'] }
  end
end
