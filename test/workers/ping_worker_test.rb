require 'test_helper'

class PingWorkerTest < ActiveSupport::TestCase
  setup do
    @host = create(:github_host)
    SyncRepositoryWorker.jobs.clear
    UpdateRepositoryWorker.jobs.clear
  end

  should 'update a repository found by its current name' do
    repository = create(:repository, host: @host, full_name: 'owner/repo', last_synced_at: 2.weeks.ago)

    PingWorker.new.perform(@host.name, 'Owner/Repo')

    assert_equal [[repository.id, false]], UpdateRepositoryWorker.jobs.map { |job| job['args'] }
    assert_empty SyncRepositoryWorker.jobs
  end

  should 'sync the pinged name when it only matches a previous name' do
    repository = create(:repository, host: @host, full_name: 'owner/repo', last_synced_at: 2.weeks.ago)
    repository.update!(full_name: 'owner/renamed')

    PingWorker.new.perform(@host.name, 'owner/repo')

    assert_equal [[@host.id, 'owner/repo']], SyncRepositoryWorker.jobs.map { |job| job['args'] }
    assert_empty UpdateRepositoryWorker.jobs
  end
end
