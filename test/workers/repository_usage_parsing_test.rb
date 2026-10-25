require 'test_helper'

class RepositoryUsageParsingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @previous_generation = ENV['REPOSITORY_USAGE_GENERATION']
    @previous_read_generation = ENV['REPOSITORY_USAGE_READ_GENERATION']
    ENV['REPOSITORY_USAGE_GENERATION'] = ENV['REPOSITORY_USAGE_READ_GENERATION'] = '1'
    Sidekiq::Testing.server_middleware { |chain| chain.add SidekiqUniqueJobs::Middleware::Server }
    @repository = create(:github_repository, dependency_job_id: 'usage-test')
    @previous_enabled = ENV['REPOSITORY_USAGE_WRITES_ENABLED']
    @previous_ids = ENV['REPOSITORY_USAGE_REPOSITORY_IDS']
    ENV['REPOSITORY_USAGE_WRITES_ENABLED'] = 'true'
    ENV['REPOSITORY_USAGE_REPOSITORY_IDS'] = @repository.id.to_s
    RepositoryUsageWorker.clear
  end

  teardown do
    ENV['REPOSITORY_USAGE_GENERATION'] = @previous_generation
    ENV['REPOSITORY_USAGE_READ_GENERATION'] = @previous_read_generation
    Sidekiq::Testing.server_middleware { |chain| chain.remove SidekiqUniqueJobs::Middleware::Server }
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

  def perform_usage
    if RepositoryUsageWorker.jobs.any?
      RepositoryUsageWorker.perform_one
    else
      RepositoryUsageWorker.new.perform(@repository.id)
    end
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
    perform_usage
    assert_equal ['lodash'], PackageUsage.pluck(:name)
    assert_equal [0, 1], PackageUsage.first.attributes.values_at('dependents_count', 'repository_usages_count')
  end

  test 'nil SHA changes replace observations while requirement-only changes leave memberships untouched' do
    parse([manifest('lodash')])
    perform_usage
    manifest_id = @repository.manifests.pick(:id)
    relationship_id = RepositoryUsage.pick(:id)
    observation_id = Dependency.pick(:id)

    parse([manifest('lodash')])
    assert_equal observation_id, Dependency.pick(:id)

    parse([manifest('lodash', requirement: '^2')])
    perform_usage
    assert_equal '^2', Dependency.pick(:requirements)
    assert_equal relationship_id, RepositoryUsage.pick(:id)
    assert_equal manifest_id, @repository.manifests.pick(:id)

    parse([manifest('express')])
    perform_usage
    assert_equal ['express'], Dependency.pluck(:package_name)
    assert_equal 0, PackageUsage.find_by!(name: 'lodash').dependents_count
    assert_equal 1, PackageUsage.find_by!(name: 'express').dependents_count
  end

  test 'empty completion removes memberships but a parse error retains previous evidence and counts' do
    parse([manifest('lodash')])
    perform_usage
    usage = PackageUsage.find_by!(name: 'lodash')
    RepositoryUsageWorker.clear
    parse([], status: 'error')
    assert_empty RepositoryUsageWorker.jobs
    perform_usage
    assert_equal 1, usage.reload.dependents_count
    assert_equal ['lodash'], Dependency.pluck(:package_name)

    parse([])
    assert_equal [[@repository.id]], RepositoryUsageWorker.jobs.pluck('args')
    perform_usage
    assert_empty RepositoryUsage.all
    assert_equal [0, 0], usage.reload.attributes.values_at('dependents_count', 'repository_usages_count')
  end

  test 'failed parsing transaction preserves the complete prior snapshot and enqueues no usage work' do
    parse([manifest('lodash')])
    perform_usage
    RepositoryUsageWorker.clear
    before = @repository.reload.dependencies_parsed_at
    Repository.any_instance.expects(:delete_old_manifests).raises(ActiveRecord::StatementInvalid, 'failed parse write')

    assert_raises(ActiveRecord::StatementInvalid) { parse([manifest('express')]) }
    assert_equal ['lodash'], Dependency.pluck(:package_name)
    assert_equal before, @repository.reload.dependencies_parsed_at
    assert_empty RepositoryUsageWorker.jobs
    assert_equal [1], PackageUsage.pluck(:repository_usages_count)
  end

  test 'disabled rollout preserves the existing parser path without scheduling usage work' do
    ENV.delete('REPOSITORY_USAGE_WRITES_ENABLED')
    parse([manifest('lodash')])

    assert_equal ['lodash'], Dependency.pluck(:package_name)
    assert_empty RepositoryUsageWorker.jobs
    assert_empty RepositoryUsage.all
  end

  test 'unchanged parses preserve manifest SHA and do not queue completed usage work' do
    parse([manifest('lodash')])
    perform_usage
    manifest_id = @repository.manifests.pick(:id)
    parse([manifest('lodash')])
    assert_empty RepositoryUsageWorker.jobs
    assert_nil @repository.manifests.pick(:sha)
    ENV.delete('REPOSITORY_USAGE_WRITES_ENABLED')
    parse([manifest('lodash')])
    assert_equal manifest_id, @repository.manifests.pick(:id)
  end

  test 'an unchanged retry enqueues usage after a failed post-commit enqueue' do
    RepositoryUsageWorker.expects(:perform_async).raises(Redis::BaseError, 'unavailable')
    assert_raises(Redis::BaseError) { parse([manifest('lodash')]) }
    assert_equal ['lodash'], Dependency.pluck(:package_name)
    RepositoryUsageWorker.unstub(:perform_async)
    parse([manifest('lodash')])
    assert_equal [[@repository.id]], RepositoryUsageWorker.jobs.pluck('args')
    perform_usage
    assert_equal 1, PackageUsage.first.repository_usages_count
  end

  test 'a changed parse with an earlier timestamp still refreshes counts' do
    parse([manifest('lodash')])
    perform_usage
    before = @repository.reload.usage_last_calculated
    travel_to 1.hour.ago do
      parse([manifest('express')])
    end
    assert_operator @repository.reload.usage_updated_at, :<, before
    assert_equal [[@repository.id]], RepositoryUsageWorker.jobs.pluck('args')
    perform_usage
    assert_equal 0, PackageUsage.find_by!(name: 'lodash').repository_usages_count
    assert_equal 1, PackageUsage.find_by!(name: 'express').repository_usages_count
    assert_equal @repository.reload.usage_updated_at, @repository.usage_last_calculated
  end
end
