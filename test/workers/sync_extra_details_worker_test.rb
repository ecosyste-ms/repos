require 'test_helper'

class SyncExtraDetailsWorkerTest < ActiveSupport::TestCase
  setup do
    SyncExtraDetailsWorker.clear
    Sidekiq::Testing.server_middleware { |chain| chain.add SidekiqUniqueJobs::Middleware::Server }
    @repository = create(:repository, files_changed: true, pushed_at: 1.day.ago)
    delete_lock
    Repository.any_instance.stubs(:parse_dependencies)
    Repository.any_instance.stubs(:download_tags)
  end

  teardown do
    SyncExtraDetailsWorker.clear
    Sidekiq::Testing.server_middleware { |chain| chain.remove SidekiqUniqueJobs::Middleware::Server }
    delete_lock
  end

  def lock_digest
    SidekiqUniqueJobs::Job.prepare('class' => SyncExtraDetailsWorker.name, 'queue' => 'extra', 'args' => [@repository.id])['lock_digest']
  end

  def delete_lock
    SidekiqUniqueJobs::Digests.new.delete_by_digest(lock_digest)
  end

  test 'queues a follow-up when a newer push arrives while running' do
    runs = 0
    Repository.any_instance.stubs(:update_metadata_files).with do
      runs += 1
      if runs == 1
        Repository.where(id: @repository.id).update_all(pushed_at: Time.current)
        SyncExtraDetailsWorker.perform_async(@repository.id)
      end
      true
    end

    SyncExtraDetailsWorker.perform_async(@repository.id)
    SyncExtraDetailsWorker.perform_one

    assert @repository.reload.files_changed?
    assert_equal 1, SyncExtraDetailsWorker.jobs.length

    SyncExtraDetailsWorker.perform_one

    assert_equal 2, runs
    assert_not @repository.reload.files_changed?
  end

  test 'keeps one queued job for repeated refreshes' do
    2.times { SyncExtraDetailsWorker.perform_async(@repository.id) }

    assert_equal 1, SyncExtraDetailsWorker.jobs.length
    assert_equal lock_digest, SyncExtraDetailsWorker.jobs.first['lock_digest']
  end
end
