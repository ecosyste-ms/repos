require 'test_helper'
require 'sidekiq/job_retry'
require 'sidekiq/api'

class RepositoryUsageWorkerTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @previous_generation = ENV['REPOSITORY_USAGE_GENERATION']
    @previous_read_generation = ENV['REPOSITORY_USAGE_READ_GENERATION']
    ENV['REPOSITORY_USAGE_GENERATION'] = ENV['REPOSITORY_USAGE_READ_GENERATION'] = '1'
    @repository = create(:repository, dependencies_parsed_at: Time.current)
    @manifest = create(:manifest, repository: @repository, ecosystem: 'npm')
    @previous_enabled = ENV['REPOSITORY_USAGE_WRITES_ENABLED']
    @previous_ids = ENV['REPOSITORY_USAGE_REPOSITORY_IDS']
    ENV['REPOSITORY_USAGE_WRITES_ENABLED'] = 'true'
    ENV['REPOSITORY_USAGE_REPOSITORY_IDS'] = @repository.id.to_s
    RepositoryUsageWorker.clear
    REDIS.del('repository_usage_backfill:1:pending', 'repository_usage_backfill:2:pending')
  end

  teardown do
    ENV['REPOSITORY_USAGE_GENERATION'] = @previous_generation
    ENV['REPOSITORY_USAGE_READ_GENERATION'] = @previous_read_generation
    ENV['REPOSITORY_USAGE_WRITES_ENABLED'] = @previous_enabled
    ENV['REPOSITORY_USAGE_REPOSITORY_IDS'] = @previous_ids
    RepositoryUsageWorker.clear
    REDIS.del('repository_usage_backfill:1:pending', 'repository_usage_backfill:2:pending')
  end

  def perform
    RepositoryUsageWorker.new.perform(@repository.id)
  end

  def dependency(name, manifest: @manifest)
    @repository.update_column(:usage_updated_at, Time.current)
    create(:dependency, repository: @repository, manifest: manifest, ecosystem: 'npm', package_name: name)
  end

  test 'creates unique memberships across current manifests and lockfiles and builds fresh counts' do
    lockfile = create(:manifest, :lockfile, repository: @repository, ecosystem: 'npm', filepath: 'package-lock.json')
    dependency('lodash')
    dependency('lodash', manifest: lockfile)
    dependency('express', manifest: lockfile)

    assert_difference ['RepositoryUsage.count', 'PackageUsage.count'], 2 do
      perform
    end
    assert_equal ['express', 'lodash'], PackageUsage.order(:name).pluck(:name)
    assert_equal [[0, 1], [0, 1]], PackageUsage.pluck(:dependents_count, :repository_usages_count)
    assert_not_nil @repository.reload.usage_last_calculated
  end

  test 'leaves unchanged relationship ids and counters untouched on retries and requirement changes' do
    observation = dependency('lodash')
    perform
    usage = PackageUsage.find_by!(key: 'npm:lodash')
    relationship_id = RepositoryUsage.where(repository_id: @repository.id).pick(:id)
    updated_at = usage.updated_at
    observation.update!(requirements: '^2')
    queries = []

    ActiveSupport::Notifications.subscribed(->(*args) { queries << args.last[:sql] }, 'sql.active_record') do
      2.times { perform }
    end

    assert_equal relationship_id, RepositoryUsage.where(repository_id: @repository.id).pick(:id)
    assert_equal [0, 1, updated_at], usage.reload.attributes.values_at('dependents_count', 'repository_usages_count', 'updated_at')
    assert_empty queries.grep(/(?:UPDATE|INSERT INTO|DELETE FROM) "(?:repository_usages|package_usages)"/)
  end

  test 'replaces one membership with two relationship writes and allows counts to decrease to zero' do
    dependency('retained')
    removed = dependency('removed')
    perform
    retained_id = RepositoryUsage.find_by!(package_usage: PackageUsage.find_by!(name: 'retained')).id
    removed.destroy!
    dependency('added')
    perform

    assert_equal retained_id, RepositoryUsage.find_by!(package_usage: PackageUsage.find_by!(name: 'retained')).id
    assert_equal ['added', 'retained'], @repository.repository_usages.joins(:package_usage).order('package_usages.name').pluck('package_usages.name')
    assert_equal [0, 0], PackageUsage.find_by!(name: 'removed').attributes.values_at('dependents_count', 'repository_usages_count')
    assert_equal [0, 1], PackageUsage.find_by!(name: 'added').attributes.values_at('dependents_count', 'repository_usages_count')
  end

  test 'excludes tag observations even when the manifest also has a repository id' do
    tag = create(:tag, repository: @repository)
    tag_manifest = create(:manifest, repository: nil, tag: tag, ecosystem: 'npm')
    tag_manifest.update_column(:repository_id, @repository.id)
    dependency('historical', manifest: tag_manifest)
    dependency('current')
    perform

    assert_equal ['current'], PackageUsage.pluck(:name)
  end

  test 'removes all duplicate relationship rows but decrements only one repository membership' do
    dependency('lodash')
    perform
    usage = PackageUsage.find_by!(name: 'lodash')
    RepositoryUsage.create!(repository: @repository, package_usage: usage)
    Dependency.where(manifest_id: @manifest.id).delete_all
    @repository.update_column(:usage_updated_at, Time.current)
    perform
    perform

    assert_empty RepositoryUsage.where(repository_id: @repository.id)
    assert_equal [0, 0], usage.reload.attributes.values_at('dependents_count', 'repository_usages_count')
  end

  test 'preserves raw case in package identity and ignores invalid observations' do
    dependency('package')
    dependency('Package')
    dependency('...')
    invalid = dependency('missing-ecosystem')
    invalid.update_column(:ecosystem, nil)
    perform

    assert_equal ['npm:Package', 'npm:package'], PackageUsage.pluck(:key).sort
  end

  test 'refuses incomplete reads without changing relationships counters or calculation time' do
    dependency('retained')
    perform
    before = @repository.reload.usage_last_calculated
    usage = PackageUsage.find_by!(name: 'retained')
    now = Time.current
    Dependency.insert_all!(Array.new(RepositoryUsage::MAX_PACKAGES_PER_READ + 1) do |i|
      { repository_id: @repository.id, manifest_id: @manifest.id, ecosystem: 'npm', package_name: "package-#{i}", created_at: now, updated_at: now }
    end)
    @repository.update_column(:usage_updated_at, Time.current)

    assert_no_difference ['RepositoryUsage.count', 'PackageUsage.count'] do
      perform
    end
    assert_equal [@repository.id.to_s], RepositoryUsageBackfillWorker.status['pending_ids']
    assert_equal before, @repository.reload.usage_last_calculated
    assert_equal 1, usage.reload.dependents_count
  end

  test 'refuses an incomplete manifest set before reading dependencies' do
    now = Time.current
    Manifest.insert_all!(Array.new(RepositoryUsage::MAX_MANIFESTS_PER_READ) do |i|
      { repository_id: @repository.id, ecosystem: 'npm', kind: 'manifest', filepath: "workspace-#{i}/package.json", created_at: now, updated_at: now }
    end)
    queries = []
    ActiveSupport::Notifications.subscribed(->(*args) { queries << args.last[:sql] }, 'sql.active_record') do
      perform
    end
    assert_empty queries.grep(/FROM "dependencies"/)
    assert_nil @repository.reload.usage_last_calculated
    RepositoryUsage.expects(:from_repository).never
    perform
  end

  test 'repairs relationships despite an inconsistent counter baseline' do
    old_usage = create(:package_usage, ecosystem: 'npm', name: 'old', key: 'npm:old', dependents_count: 12, repository_usages_count: 1)
    RepositoryUsage.create!(repository: @repository, package_usage: old_usage)
    dependency('new')

    perform
    assert_equal ['new'], @repository.repository_usages.joins(:package_usage).pluck('package_usages.name')
    assert_equal 1, @repository.reload.usage_count_generation
    assert_equal 0, old_usage.reload.dependents_count
    assert_equal [12, 1], old_usage.reload.attributes.values_at('dependents_count', 'repository_usages_count')
  end

  test 'rolls back count changes when a relationship write fails' do
    dependency('lodash')
    perform
    usage = PackageUsage.find_by!(name: 'lodash')
    dependency('express')
    RepositoryUsage.expects(:insert_all!).raises(ActiveRecord::StatementInvalid, 'write failed')

    assert_raises(ActiveRecord::StatementInvalid) { perform }
    assert_equal [0, 1], usage.reload.attributes.values_at('dependents_count', 'repository_usages_count')
    assert_nil PackageUsage.find_by(name: 'express')
    assert_equal [usage.id], RepositoryUsage.pluck(:package_usage_id)
  end

  test 'destroying a repository decrements unique memberships in its destroy transaction' do
    dependency('lodash')
    perform
    usage = PackageUsage.find_by!(name: 'lodash')
    RepositoryUsage.create!(repository: @repository, package_usage: usage)
    @repository.destroy!

    assert_empty RepositoryUsage.all
    assert_equal [0, 0], usage.reload.attributes.values_at('dependents_count', 'repository_usages_count')
    assert_nil RepositoryUsageWorker.new.perform(@repository.id)
  end

  test 'disabled worker and direct entrypoint do no usage reads or writes' do
    dependency('lodash')
    ENV.delete('REPOSITORY_USAGE_WRITES_ENABLED')
    RepositoryUsage.expects(:packages_for_repository).never
    assert_no_difference ['RepositoryUsage.count', 'PackageUsage.count'] do
      assert_nil perform
      assert_nil RepositoryUsage.from_repository(@repository)
    end
  end

  test 'allowlist excludes other repositories' do
    ENV['REPOSITORY_USAGE_REPOSITORY_IDS'] = (@repository.id + 1).to_s
    RepositoryUsage.expects(:packages_for_repository).never
    assert_nil perform
  end

  test 'skips repositories that have not completed parsing' do
    @repository.update_column(:dependencies_parsed_at, nil)
    dependency('lodash')
    assert_no_difference 'RepositoryUsage.count' do
      perform
    end
  end

  test 'concurrent maintenance retries instead of inserting duplicate memberships' do
    dependency('lodash')
    error = nil
    RepositoryUsage.transaction do
      RepositoryUsage.lock_repository(@repository.id)
      thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection(prevent_permanent_checkout: true) do
          RepositoryUsageWorker.new.perform(@repository.id)
        rescue => exception
          error = exception
        end
      end
      assert thread.join(5), 'Worker did not finish within the lock test budget'
    ensure
      thread&.kill if thread&.alive?
    end

    assert_instance_of ActiveRecord::LockWaitTimeout, error
    assert_empty RepositoryUsage.all
    perform
    perform
    assert_equal 1, RepositoryUsage.count
    assert_equal [0, 1], PackageUsage.first.attributes.values_at('dependents_count', 'repository_usages_count')
  end

  test 'a parse committing during maintenance cannot commit a stale membership set' do
    dependency('old')
    changed = false
    callback = lambda do |*args|
      next unless args.last[:sql].include?('FROM "dependencies"') && !changed
      changed = true
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection(prevent_permanent_checkout: true) do
          Repository.transaction do
            Dependency.where(manifest_id: @manifest.id).delete_all
            dependency('new')
            Repository.where(id: @repository.id).update_all(dependencies_parsed_at: Time.current)
          end
        end
      end.value
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      assert_raises(ActiveRecord::SerializationFailure) { perform }
    end
    assert_empty RepositoryUsage.all
    assert_empty PackageUsage.all
    assert_nil @repository.reload.usage_last_calculated

    perform
    assert_equal ['new'], PackageUsage.pluck(:name)
    assert_equal [1], PackageUsage.pluck(:repository_usages_count)
  end

  test 'sets query safeguards only for the maintenance transaction' do
    sql = "SELECT current_setting('statement_timeout') AS statement_timeout, current_setting('lock_timeout') AS lock_timeout, current_setting('jit') AS jit, current_setting('max_parallel_workers_per_gather') AS parallel_workers"
    before = RepositoryUsage.uncached { RepositoryUsage.connection.select_one(sql) }
    settings = nil
    RepositoryUsage.expects(:packages_for_repository).with do |repository, **options|
      settings = RepositoryUsage.uncached { RepositoryUsage.connection.select_one(sql) }
      repository.id == @repository.id
    end.returns([])
    perform

    assert_equal ['2s', '250ms', 'off', '0'], settings.values_at('statement_timeout', 'lock_timeout', 'jit', 'parallel_workers')
    assert_equal before, RepositoryUsage.uncached { RepositoryUsage.connection.select_one(sql) }
  end

  test 'unchanged legacy memberships contribute once regardless of old counters' do
    [nil, -3, 99].each_with_index do |old_count, index|
      usage = create(:package_usage, ecosystem: 'npm', name: "package-#{index}", key: "npm:package-#{index}", dependents_count: 99, repository_usages_count: old_count)
      2.times { RepositoryUsage.create!(repository: @repository, package_usage: usage) }
      dependency(usage.name)
    end
    before = RepositoryUsage.order(:id).pluck(:id)
    2.times { perform }
    assert_equal before, RepositoryUsage.order(:id).pluck(:id)
    assert_equal [1, 1, 1], PackageUsage.order(:id).pluck(:repository_usages_count)
    assert_equal [99, 99, 99], PackageUsage.order(:id).pluck(:dependents_count)
  end

  test 'empty uncounted repositories are not rewritten' do
    queries = []
    ActiveSupport::Notifications.subscribed(->(*args) { queries << args.last[:sql] }, 'sql.active_record') { perform }
    assert_nil @repository.reload.usage_count_generation
    assert_empty queries.grep(/UPDATE|INSERT INTO|DELETE FROM/)
  end

  test 'a new generation counts each repository once and ignores old generation deletions' do
    ENV.delete('REPOSITORY_USAGE_REPOSITORY_IDS')
    other = create(:repository, dependencies_parsed_at: Time.current)
    other_manifest = create(:manifest, repository: other)
    dependency('shared')
    create(:dependency, repository: other, manifest: other_manifest, ecosystem: 'npm', package_name: 'shared')
    perform
    RepositoryUsageWorker.new.perform(other.id)
    usage = PackageUsage.find_by!(name: 'shared')
    assert_equal 2, usage.repository_usages_count
    ENV['REPOSITORY_USAGE_GENERATION'] = '2'
    2.times { perform }
    assert_equal 1, usage.reload.repository_usages_count
    other.destroy!
    assert_equal 1, usage.reload.repository_usages_count
    ENV['REPOSITORY_USAGE_GENERATION'] = '1'
    perform
    assert_equal [@repository.id.to_s], RepositoryUsageBackfillWorker.status['pending_ids']
    assert_equal 1, usage.reload.repository_usages_count
  end

  test 'exhausted transient failures remain visible without suppressing later parse jobs' do
    dependency('shared')
    worker = RepositoryUsageWorker.new
    jid = SecureRandom.hex(12)
    payload = Sidekiq.dump_json('class' => worker.class.name, 'args' => [@repository.id], 'queue' => 'usage', 'jid' => jid, 'retry' => 0)
    RepositoryUsage.expects(:from_repository).raises(ActiveRecord::QueryCanceled)
    assert_raises(Sidekiq::JobRetry::Handled) do
      Sidekiq::JobRetry.new(Sidekiq.default_configuration).local(worker, payload, 'usage') { worker.perform(@repository.id) }
    end
    dead_job = Sidekiq::DeadSet.new.find_job(jid)
    assert_not_nil dead_job
    assert_equal 0, RepositoryUsageBackfillWorker.status['pending']
    RepositoryUsage.unstub(:from_repository)
    perform
    assert_equal 1, PackageUsage.first.repository_usages_count
  ensure
    dead_job&.delete
  end

  test 'deletion waits for maintenance and reverses contributions even when writes are disabled' do
    dependency('shared')
    perform
    held = Queue.new
    release = Queue.new
    lock_holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(prevent_permanent_checkout: true) do
        RepositoryUsage.transaction do
          RepositoryUsage.lock_repository(@repository.id)
          held << true
          release.pop
        end
      end
    end
    held.pop
    ENV.delete('REPOSITORY_USAGE_WRITES_ENABLED')
    deleter = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(prevent_permanent_checkout: true) do
        Repository.find(@repository.id).destroy_without_statement_timeout!
      end
    end
    assert_nil deleter.join(0.1)
    release << true
    lock_holder.value
    assert deleter.join(5)
    deleter.value
    assert_equal 0, PackageUsage.find_by!(name: 'shared').repository_usages_count
  ensure
    release << true if release
    [lock_holder, deleter].compact.each { |thread| thread.kill if thread.alive? }
  end
end
