require 'test_helper'

class RepositoryUsageParsingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @repository = create(:github_repository, dependency_job_id: 'usage-test')
    @previous_enabled = ENV['REPOSITORY_USAGE_WRITES_ENABLED']
    @previous_ids = ENV['REPOSITORY_USAGE_REPOSITORY_IDS']
    ENV['REPOSITORY_USAGE_WRITES_ENABLED'] = 'true'
    ENV['REPOSITORY_USAGE_REPOSITORY_IDS'] = @repository.id.to_s
    RepositoryUsageWorker.clear
  end

  teardown do
    ENV['REPOSITORY_USAGE_WRITES_ENABLED'] = @previous_enabled
    ENV['REPOSITORY_USAGE_REPOSITORY_IDS'] = @previous_ids
    RepositoryUsageWorker.clear
  end

  def parse(manifests, status: 'complete')
    @repository.update_column(:dependency_job_id, 'usage-test')
    stub_request(:get, "#{PARSER_DOMAIN}/api/v1/jobs/usage-test").to_return(
      status: 200,
      body: { id: 'usage-test', status: status, results: { manifests: manifests } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    ParseDependenciesWorker.new.perform(@repository.id)
  end

  def manifest(name, requirement: '^1', sha: nil)
    { platform: 'npm', path: 'package.json', kind: 'manifest', sha: sha,
      dependencies: [{ name: name, requirement: requirement, type: 'runtime' }] }
  end

  test 'parser completion queues usage after commit and the worker reconciles persisted observations' do
    seen_committed = false
    RepositoryUsageWorker.expects(:perform_async).with do |id|
      seen_committed = !Repository.connection.transaction_open? && @repository.reload.usage_updated_at.present?
      id == @repository.id
    end
    parse([manifest('lodash')])

    assert seen_committed
    assert_empty RepositoryUsage.all
    RepositoryUsageWorker.new.perform(@repository.id)
    assert_equal ['lodash'], PackageUsage.pluck(:name)
    assert_equal [1, 1], PackageUsage.first.attributes.values_at('dependents_count', 'repository_usages_count')
  end

  test 'nil SHA changes replace observations while requirement-only changes leave memberships untouched' do
    parse([manifest('lodash')])
    RepositoryUsageWorker.new.perform(@repository.id)
    manifest_id = @repository.manifests.pick(:id)
    relationship_id = RepositoryUsage.pick(:id)
    observation_id = Dependency.pick(:id)

    parse([manifest('lodash')])
    assert_equal observation_id, Dependency.pick(:id)

    parse([manifest('lodash', requirement: '^2')])
    RepositoryUsageWorker.new.perform(@repository.id)
    assert_equal '^2', Dependency.pick(:requirements)
    assert_equal relationship_id, RepositoryUsage.pick(:id)
    assert_equal manifest_id, @repository.manifests.pick(:id)

    parse([manifest('express')])
    RepositoryUsageWorker.new.perform(@repository.id)
    assert_equal ['express'], Dependency.pluck(:package_name)
    assert_equal 0, PackageUsage.find_by!(name: 'lodash').dependents_count
    assert_equal 1, PackageUsage.find_by!(name: 'express').dependents_count
  end

  test 'empty completion removes memberships but a parse error retains previous evidence and counts' do
    parse([manifest('lodash')])
    RepositoryUsageWorker.new.perform(@repository.id)
    usage = PackageUsage.find_by!(name: 'lodash')
    RepositoryUsageWorker.clear
    parse([], status: 'error')
    assert_empty RepositoryUsageWorker.jobs
    RepositoryUsageWorker.new.perform(@repository.id)
    assert_equal 1, usage.reload.dependents_count
    assert_equal ['lodash'], Dependency.pluck(:package_name)

    parse([])
    assert_equal [[@repository.id]], RepositoryUsageWorker.jobs.pluck('args')
    RepositoryUsageWorker.new.perform(@repository.id)
    assert_empty RepositoryUsage.all
    assert_equal [0, 0], usage.reload.attributes.values_at('dependents_count', 'repository_usages_count')
  end

  test 'failed parsing transaction preserves the complete prior snapshot and enqueues no usage work' do
    parse([manifest('lodash')])
    RepositoryUsageWorker.new.perform(@repository.id)
    RepositoryUsageWorker.clear
    before = @repository.reload.dependencies_parsed_at
    Repository.any_instance.expects(:delete_old_manifests).raises(ActiveRecord::StatementInvalid, 'failed parse write')

    assert_raises(ActiveRecord::StatementInvalid) { parse([manifest('express')]) }
    assert_equal ['lodash'], Dependency.pluck(:package_name)
    assert_equal before, @repository.reload.dependencies_parsed_at
    assert_empty RepositoryUsageWorker.jobs
    assert_equal [1], PackageUsage.pluck(:dependents_count)
  end

  test 'disabled rollout preserves the existing parser path without scheduling usage work' do
    ENV.delete('REPOSITORY_USAGE_WRITES_ENABLED')
    parse([manifest('lodash')])

    assert_equal ['lodash'], Dependency.pluck(:package_name)
    assert_empty RepositoryUsageWorker.jobs
    assert_empty RepositoryUsage.all
  end
end
