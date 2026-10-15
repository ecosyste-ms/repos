require 'test_helper'
require 'rake'

class ReleasesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('releases:backfill_immutability')
    Rake::Task['releases:backfill_immutability'].reenable
    Rake::Task['releases:backfill_tag_links'].reenable
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

  test 'backfill_tag_links links releases for known GitHub repositories' do
    github_host = create(:github_host)
    first_repository = create(:repository, host: github_host, full_name: 'actions/checkout')
    second_repository = create(:repository, host: github_host, full_name: 'actions/setup-node')
    first_tag = create(:tag, repository: first_repository, name: 'v4.0.0')
    second_tag = create(:tag, repository: second_repository, name: 'v3.0.0')
    first_release = create(:release, repository: first_repository, tag_name: 'v4.0.0')
    second_release = create(:release, repository: second_repository, tag_name: 'v3.0.0')
    repository_names = Set.new([first_repository.full_name, second_repository.full_name.upcase, 'missing/action'])
    Repository.expects(:github_actions_package_names).returns(repository_names)

    output = capture_io do
      Rake::Task['releases:backfill_tag_links'].invoke
    end.first

    assert_includes output, 'Processed 1 names, linked 1 releases, missing 0, last name actions/checkout'
    assert_includes output, 'Done: processed 3 names, linked 2 releases, missing 1; last name missing/action'
    assert_equal first_tag.id, first_release.reload.tag_id
    assert_equal second_tag.id, second_release.reload.tag_id
  end

  test 'backfill_tag_links resumes after the given name' do
    github_host = create(:github_host)
    skipped_repository = create(:repository, host: github_host, full_name: 'actions/cache')
    resumed_repository = create(:repository, host: github_host, full_name: 'actions/checkout')
    create(:tag, repository: skipped_repository, name: 'v4.0.0')
    create(:tag, repository: resumed_repository, name: 'v4.0.0')
    skipped_release = create(:release, repository: skipped_repository, tag_name: 'v4.0.0')
    resumed_release = create(:release, repository: resumed_repository, tag_name: 'v4.0.0')
    Repository.expects(:github_actions_package_names)
      .returns(Set.new([skipped_repository.full_name, resumed_repository.full_name]))

    output = capture_io do
      Rake::Task['releases:backfill_tag_links'].invoke('actions/cache')
    end.first

    assert_includes output, 'Done: processed 1 names, linked 1 releases, missing 0; last name actions/checkout'
    assert_nil skipped_release.reload.tag_id
    assert_not_nil resumed_release.reload.tag_id
  end

  test 'backfill_tag_links aborts without a GitHub host' do
    Repository.expects(:github_actions_package_names).never

    _output, errors = capture_io do
      assert_raises(SystemExit) { Rake::Task['releases:backfill_tag_links'].invoke }
    end

    assert_includes errors, 'Unable to find the GitHub host'
  end
end
