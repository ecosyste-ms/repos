require 'test_helper'

class RepositoryUsageWorkerTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @repository = create(:repository, dependencies_parsed_at: Time.current)
    @manifest = create(:manifest, repository: @repository, ecosystem: 'npm')
  end

  def preview
    RepositoryUsageWorker.new.perform(@repository.id, true)
  end

  test 'preview deduplicates current manifests and lockfiles without changing usage state' do
    lockfile = create(:manifest, :lockfile, repository: @repository, ecosystem: 'npm', filepath: 'package-lock.json')
    create(:dependency, repository: @repository, manifest: @manifest, ecosystem: 'npm', package_name: 'lodash')
    create(:dependency, repository: @repository, manifest: lockfile, ecosystem: 'npm', package_name: 'lodash')
    create(:dependency, repository: @repository, manifest: lockfile, ecosystem: 'npm', package_name: 'express')
    usage = create(:package_usage, ecosystem: 'npm', name: 'existing', key: 'npm:existing', dependents_count: 42)
    existing = RepositoryUsage.create!(repository: @repository, package_usage: usage)

    assert_no_difference ['RepositoryUsage.count', 'PackageUsage.count', 'Dependency.count', 'Manifest.count'] do
      assert_equal [['npm', 'express'], ['npm', 'lodash']], preview.sort
    end
    assert_equal existing.id, RepositoryUsage.where(repository: @repository).pick(:id)
    assert_equal 42, usage.reload.dependents_count
    assert_nil @repository.reload.usage_last_calculated
  end

  test 'preview excludes tag observations even when they have the same repository id' do
    tag = create(:tag, repository: @repository)
    tag_manifest = create(:manifest, repository: nil, tag: tag, ecosystem: 'npm')
    tag_manifest.update_column(:repository_id, @repository.id)
    create(:dependency, repository: @repository, manifest: tag_manifest, ecosystem: 'npm', package_name: 'historical')
    create(:dependency, repository: @repository, manifest: @manifest, ecosystem: 'npm', package_name: 'current')

    assert_equal [['npm', 'current']], preview
  end

  test 'preview does not query dependencies for a repository without manifests' do
    @manifest.destroy!
    queries = []
    callback = ->(*args) { queries << args.last[:sql] }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      assert_equal [], preview
    end
    assert_empty queries.grep(/FROM "dependencies"/)
  end

  test 'preview reads fresh manifest ids after bulk deletion' do
    create(:dependency, repository: @repository, manifest: @manifest, ecosystem: 'npm', package_name: 'deleted')
    @repository.manifests.load
    Manifest.where(id: @manifest.id).delete_all
    Repository.expects(:find).with(@repository.id).returns(@repository)

    assert_equal [], preview
  end

  test 'preview falls back to SQL distinct for larger inputs without losing memberships' do
    now = Time.current
    Dependency.insert_all!(Array.new(RepositoryUsage::MAX_RAW_DEPENDENCIES + 1) do |i|
      { repository_id: @repository.id, manifest_id: @manifest.id, ecosystem: 'npm', package_name: "package-#{i}", requirements: '^1', created_at: now, updated_at: now }
    end)

    packages = preview
    assert_equal RepositoryUsage::MAX_RAW_DEPENDENCIES + 1, packages.length
    assert_includes packages, ['npm', 'package-0']
    assert_includes packages, ['npm', "package-#{RepositoryUsage::MAX_RAW_DEPENDENCIES}"]
  end

  test 'Ruby and SQL paths preserve raw identity including null and case' do
    expected = [['npm', 'package'], ['npm', 'Package'], [nil, 'package'], ['', 'package']]
    now = Time.current
    rows = expected.map do |ecosystem, name|
      { repository_id: @repository.id, manifest_id: @manifest.id, ecosystem: ecosystem, package_name: name, created_at: now, updated_at: now }
    end
    Dependency.insert_all!(rows)
    assert_equal expected.to_set, preview.to_set

    Dependency.insert_all!(Array.new(RepositoryUsage::MAX_RAW_DEPENDENCIES + 1) { rows.first })
    assert_equal expected.to_set, preview.to_set
  end

  test 'preview refuses an incomplete package set' do
    now = Time.current
    Dependency.insert_all!(Array.new(RepositoryUsage::MAX_PACKAGES_PER_READ + 1) do |i|
      { repository_id: @repository.id, manifest_id: @manifest.id, ecosystem: 'npm', package_name: "package-#{i}", created_at: now, updated_at: now }
    end)

    assert_raises(RepositoryUsage::ReadLimitExceeded) { preview }
    assert_nil @repository.reload.usage_last_calculated
  end

  test 'preview refuses an incomplete manifest set before reading dependencies' do
    now = Time.current
    Manifest.insert_all!(Array.new(RepositoryUsage::MAX_MANIFESTS_PER_READ) do |i|
      { repository_id: @repository.id, ecosystem: 'npm', kind: 'manifest', filepath: "workspace-#{i}/package.json", created_at: now, updated_at: now }
    end)
    queries = []
    callback = ->(*args) { queries << args.last[:sql] }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      assert_raises(RepositoryUsage::ReadLimitExceeded) { preview }
    end
    assert_empty queries.grep(/FROM "dependencies"/)
  end

  test 'preview uses a read-only snapshot with transaction-local query safeguards' do
    settings = nil
    reset_query = "SELECT current_setting('statement_timeout') AS statement_timeout, current_setting('lock_timeout') AS lock_timeout, current_setting('jit') AS jit, current_setting('max_parallel_workers_per_gather') AS parallel_workers"
    before = RepositoryUsage.connection.select_one(reset_query)
    RepositoryUsage.expects(:packages_for_repository).with do |repository|
      settings = RepositoryUsage.connection.select_one("SELECT current_setting('transaction_read_only') AS read_only, current_setting('transaction_isolation') AS isolation, current_setting('statement_timeout') AS statement_timeout, current_setting('lock_timeout') AS lock_timeout, current_setting('jit') AS jit, current_setting('max_parallel_workers_per_gather') AS parallel_workers")
      repository.id == @repository.id
    end.returns([])

    preview
    assert_equal ['on', 'repeatable read', '2s', '250ms', 'off', '0'], settings.values_at('read_only', 'isolation', 'statement_timeout', 'lock_timeout', 'jit', 'parallel_workers')
    assert_equal 'off', RepositoryUsage.connection.select_value("SHOW transaction_read_only")
    assert_equal before, RepositoryUsage.connection.select_one(reset_query)
  end

  test 'ordinary worker calls retain the disabled rebuild behaviour' do
    RepositoryUsage.expects(:packages_for_repository).never

    assert_no_difference 'RepositoryUsage.count' do
      assert_nil RepositoryUsageWorker.new.perform(@repository.id)
    end
  end
end
