require 'test_helper'

class RepositoryUsageBackfillWorkerTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @previous = ENV.to_h.slice('REPOSITORY_USAGE_GENERATION', 'REPOSITORY_USAGE_WRITES_ENABLED', 'REPOSITORY_USAGE_REPOSITORY_IDS')
    ENV['REPOSITORY_USAGE_GENERATION'] = '171'
    ENV['REPOSITORY_USAGE_WRITES_ENABLED'] = 'true'
    ENV.delete('REPOSITORY_USAGE_REPOSITORY_IDS')
    clear_progress
    RepositoryUsageBackfillWorker.clear
    Sidekiq::Testing.server_middleware { |chain| chain.add SidekiqUniqueJobs::Middleware::Server }
    @repository = create(:repository, dependencies_parsed_at: Time.current)
    @manifest = create(:manifest, repository: @repository)
    create(:dependency, repository: @repository, manifest: @manifest, ecosystem: 'npm', package_name: 'shared')
    @package = create(:package_usage, ecosystem: 'npm', name: 'shared', key: 'npm:shared', dependents_count: 900, repository_usages_count: nil)
  end

  teardown do
    clear_progress
    RepositoryUsageBackfillWorker.clear
    Sidekiq::Testing.server_middleware { |chain| chain.remove SidekiqUniqueJobs::Middleware::Server }
    @previous.each { |key, value| ENV[key] = value }
    %w[REPOSITORY_USAGE_GENERATION REPOSITORY_USAGE_WRITES_ENABLED REPOSITORY_USAGE_REPOSITORY_IDS].each { |key| ENV.delete(key) unless @previous.key?(key) }
  end

  def clear_progress
    REDIS.del('repository_usage_backfill:171', 'repository_usage_backfill:171:pending')
  end

  def perform
    RepositoryUsageBackfillWorker.new.perform(171)
  end

  test 'one pass skips unparsed and empty repositories and stops after completion' do
    unparsed = create(:repository)
    empty = create(:repository, dependencies_parsed_at: Time.current)
    perform
    assert_equal [900, 1], @package.reload.attributes.values_at('dependents_count', 'repository_usages_count')
    assert_nil unparsed.reload.usage_count_generation
    assert_nil empty.reload.usage_count_generation
    assert_nil empty.usage_last_calculated
    RepositoryUsageBackfillWorker.clear
    perform
    assert RepositoryUsageBackfillWorker.status['ready']
    assert_empty RepositoryUsageBackfillWorker.jobs
    travel 8.days do
      perform
      assert_empty RepositoryUsageBackfillWorker.jobs
    end
  end

  test 'replayed cursor and lost progress cannot double count a contribution' do
    2.times do
      perform
      clear_progress
    end
    assert_equal 1, @package.reload.repository_usages_count
  end

  test 'a failed repository remains pending while later repositories are processed' do
    later = create(:repository, dependencies_parsed_at: Time.current)
    manifest = create(:manifest, repository: later)
    create(:dependency, repository: later, manifest: manifest, ecosystem: 'npm', package_name: 'later')
    RepositoryUsage.expects(:packages_for_repository).with { |repository, **| repository.id == @repository.id }.raises(RepositoryUsage::ReadLimitExceeded)
    RepositoryUsage.expects(:packages_for_repository).with { |repository, **| repository.id == later.id }.returns([['npm', 'later']])
    perform
    perform
    status = RepositoryUsageBackfillWorker.status
    assert_equal 'true', status['finished']
    assert_not status['ready']
    assert_equal [@repository.id.to_s], status['pending_ids']
    assert_equal 1, PackageUsage.find_by!(name: 'later').repository_usages_count
    RepositoryUsage.unstub(:packages_for_repository)
    assert RepositoryUsageBackfillWorker.retry_repository(@repository.id)
    assert RepositoryUsageBackfillWorker.status['ready']
    assert_equal 1, @package.reload.repository_usages_count
  end

  test 'manual retry can raise a read limit and statement timeout without resetting progress' do
    now = Time.current
    Manifest.insert_all!(Array.new(RepositoryUsage::MAX_MANIFESTS_PER_READ) { |i| {repository_id: @repository.id, filepath: "#{i}.json", created_at: now, updated_at: now} })
    perform
    assert_equal 1, RepositoryUsageBackfillWorker.status['pending']
    settings = []
    callback = ->(*args) { settings << args.last[:sql] if args.last[:sql].include?('SET LOCAL statement_timeout') }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      assert RepositoryUsageBackfillWorker.retry_repository(@repository.id, max_manifests: 2_000, statement_timeout: '5s')
    end
    assert_includes settings, "SET LOCAL statement_timeout = '5s'"
    assert_equal 0, RepositoryUsageBackfillWorker.status['pending']
    assert_equal 1, @package.reload.repository_usages_count
  end

  test 'disabled allowlisted and obsolete generation jobs do not advance coverage' do
    ENV['REPOSITORY_USAGE_REPOSITORY_IDS'] = @repository.id.to_s
    perform
    ENV.delete('REPOSITORY_USAGE_REPOSITORY_IDS')
    RepositoryUsageBackfillWorker.new.perform(170)
    ENV.delete('REPOSITORY_USAGE_WRITES_ENABLED')
    perform
    assert_empty REDIS.hgetall(RepositoryUsageBackfillWorker.key)
    assert_nil @repository.reload.usage_count_generation
  end

  test 'repeated crawl requests keep one queued continuation' do
    SidekiqUniqueJobs::Digests.new.delete_by_pattern('*')
    2.times { RepositoryUsage.crawl }
    assert_equal 1, RepositoryUsageBackfillWorker.jobs.length
    RepositoryUsageBackfillWorker.perform_one
    assert_equal 1, RepositoryUsageBackfillWorker.jobs.length
    2.times { RepositoryUsage.crawl }
    assert_equal 1, RepositoryUsageBackfillWorker.jobs.length
    RepositoryUsageBackfillWorker.perform_one
    assert RepositoryUsageBackfillWorker.status['ready']
    assert_empty RepositoryUsageBackfillWorker.jobs
  end
end
