require 'test_helper'

class SyncInactiveRepositoryWorkerTest < ActiveSupport::TestCase
  context '#perform' do
    should 'sync a repository that has never been synced' do
      repository = create(:repository, last_synced_at: nil)
      Repository.any_instance.expects(:sync).once

      SyncInactiveRepositoryWorker.new.perform(repository.id)
    end

    should 'sync an inactive repository' do
      repository = create(:repository, last_synced_at: 2.weeks.ago)
      Repository.any_instance.expects(:sync).once

      SyncInactiveRepositoryWorker.new.perform(repository.id)
    end

    should 'sync a repository last synced exactly one week ago' do
      travel_to Time.zone.local(2026, 7, 22, 12) do
        repository = create(:repository, last_synced_at: 1.week.ago)
        Repository.any_instance.expects(:sync).once

        SyncInactiveRepositoryWorker.new.perform(repository.id)
      end
    end

    should 'skip a recently synced repository' do
      repository = create(:repository, last_synced_at: 1.day.ago)
      Repository.any_instance.expects(:sync).never

      SyncInactiveRepositoryWorker.new.perform(repository.id)
    end

    should 'skip a fork' do
      repository = create(:repository, fork: true, last_synced_at: 2.weeks.ago)
      Repository.any_instance.expects(:sync).never

      SyncInactiveRepositoryWorker.new.perform(repository.id)
    end

    should 'skip an archived repository' do
      repository = create(:repository, archived: true, last_synced_at: 2.weeks.ago)
      Repository.any_instance.expects(:sync).never

      SyncInactiveRepositoryWorker.new.perform(repository.id)
    end

    should 'handle a missing repository' do
      assert_nothing_raised do
        SyncInactiveRepositoryWorker.new.perform(-1)
      end
    end
  end
end
