require 'test_helper'
require 'rake'

class RepositoriesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('repositories:sync_inactive')
  end

  test 'sync_inactive queues a batch when the default queue has capacity' do
    CronLock.expects(:acquire).with('repositories:sync_inactive', ttl: 20.minutes).yields
    Sidekiq::Queue.any_instance.stubs(:size).returns(0)
    Repository.expects(:enqueue_inactive_sync_batch).once

    Rake::Task['repositories:sync_inactive'].execute
  end

  test 'sync_inactive skips the batch when the default queue is full' do
    CronLock.expects(:acquire).with('repositories:sync_inactive', ttl: 20.minutes).yields
    Sidekiq::Queue.any_instance.stubs(:size).returns(10_000)
    Repository.expects(:enqueue_inactive_sync_batch).never

    Rake::Task['repositories:sync_inactive'].execute
  end
  test 'sync_extra_details queues up to the remaining extra queue capacity' do
    CronLock.expects(:acquire).with('repositories:sync_extra_details', ttl: 10.minutes).yields
    Sidekiq::Queue.any_instance.stubs(:size).returns(Repository::EXTRA_DETAILS_QUEUE_LIMIT - 10)
    Repository.expects(:sync_extra_details_async).with(limit: 10).once

    Rake::Task['repositories:sync_extra_details'].execute
  end

  test 'sync_extra_details skips the batch when the extra queue is full' do
    CronLock.expects(:acquire).with('repositories:sync_extra_details', ttl: 10.minutes).yields
    Sidekiq::Queue.any_instance.stubs(:size).returns(Repository::EXTRA_DETAILS_QUEUE_LIMIT)
    Repository.expects(:sync_extra_details_async).never

    Rake::Task['repositories:sync_extra_details'].execute
  end
end
