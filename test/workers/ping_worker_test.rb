require 'test_helper'

class PingWorkerTest < ActiveSupport::TestCase
  setup do
    @unique_jobs_enabled = SidekiqUniqueJobs.config.enabled
    SidekiqUniqueJobs.config.enabled = false
    @host = create(:github_host)
    [SyncExtraDetailsWorker, UpdateRepositoryWorker].each(&:clear)
  end

  teardown do
    [SyncExtraDetailsWorker, UpdateRepositoryWorker].each(&:clear)
    SidekiqUniqueJobs.config.enabled = @unique_jobs_enabled
  end

  test 'enqueues pending metadata for a recently synced repository' do
    repository = create(:repository, host: @host, full_name: 'openwisp/.github', owner: 'openwisp', files_changed: true, last_synced_at: 1.day.ago)

    PingWorker.new.perform(@host.name, repository.full_name)

    assert_equal [[repository.id]], SyncExtraDetailsWorker.jobs.map { |job| job['args'] }
    assert_equal [[repository.id]], UpdateRepositoryWorker.jobs.map { |job| job['args'] }
  end

  test 'does not enqueue metadata for a recently synced repository without changes' do
    repository = create(:repository, host: @host, files_changed: false, last_synced_at: 1.day.ago)

    PingWorker.new.perform(@host.name, repository.full_name)

    assert_empty SyncExtraDetailsWorker.jobs
  end

  test 'does not enqueue metadata for a fork' do
    repository = create(:repository, host: @host, fork: true, files_changed: true, last_synced_at: 1.day.ago)

    PingWorker.new.perform(@host.name, repository.full_name)

    assert_empty SyncExtraDetailsWorker.jobs
  end
end
