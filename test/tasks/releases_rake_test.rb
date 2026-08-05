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
      .yields(1, 1, 0, 'actions/checkout')
      .returns([1, 1, 0, 'actions/checkout'])

    output = capture_io do
      Rake::Task['releases:backfill_immutability'].invoke(250, 'actions/cache')
    end.first

    assert_includes output, 'last name actions/checkout'
  end
end
