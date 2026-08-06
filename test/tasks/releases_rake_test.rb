require 'test_helper'
require 'rake'

class ReleasesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('releases:backfill_immutability')
    Rake::Task['releases:backfill_immutability'].reenable
  end

  test 'backfill_immutability loads Action names and passes cursor arguments' do
    repository_names = Set.new(['actions/checkout'])
    Repository.expects(:github_actions_package_names).returns(repository_names)
    Release.expects(:backfill_immutability)
      .with(repository_names: repository_names, block_size: 250, after_name: 'actions/cache')
      .yields(1, 1, 0, 'actions/checkout', 0, nil)
      .returns([1, 1, 0, 'actions/checkout', 0])

    output = capture_io do
      Rake::Task['releases:backfill_immutability'].invoke(250, 'actions/cache')
    end.first

    assert_includes output, 'last name actions/checkout'
    assert_includes output, 'failed 0'
  end

  test 'backfill_immutability reports repository sync failures' do
    repository_names = Set.new(['actions/failing'])
    error = Octokit::ServerError.new(status: 504, body: 'timeout')
    Repository.expects(:github_actions_package_names).returns(repository_names)
    Release.expects(:backfill_immutability)
      .with(repository_names: repository_names, block_size: 1_000, after_name: nil)
      .yields(1, 0, 0, 'actions/failing', 1, error)
      .returns([1, 0, 0, 'actions/failing', 1])

    output, errors = capture_io do
      Rake::Task['releases:backfill_immutability'].invoke
    end

    assert_includes output, 'failed 1'
    assert_includes errors, 'Failed to sync actions/failing: Octokit::ServerError'
  end
end
