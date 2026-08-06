require "test_helper"

class ReleaseTest < ActiveSupport::TestCase
  setup do
    @repository = create(:repository)
    @release = create(:release, repository: @repository, tag_name: 'v1.0.0')
  end

  test 'semantic version parsing' do
    assert_equal '1.0.0', @release.clean_number
    assert_not_nil @release.semantic_version
  end

  test 'semantic version comparison' do
    release1 = create(:release, repository: @repository, tag_name: 'v1.0.0')
    release2 = create(:release, repository: @repository, tag_name: 'v2.0.0')
    release3 = create(:release, repository: @repository, tag_name: 'v1.5.0')

    sorted = [release1, release2, release3].sort
    assert_equal [release2, release3, release1], sorted
  end

  test 'non-semver tags fall back to string comparison' do
    release1 = create(:release, repository: @repository, tag_name: 'latest')
    release2 = create(:release, repository: @repository, tag_name: 'main')

    sorted = [release1, release2].sort
    assert_equal 2, sorted.length
  end

  test 'handles versions with leading zeros' do
    release = create(:release, repository: @repository, tag_name: 'v1.09.0')
    assert_not_nil release.clean_number
    assert_nothing_raised { release.semantic_version }
  end

  test 'comparison with leading zeros works' do
    release1 = create(:release, repository: @repository, tag_name: 'v1.09.0')
    release2 = create(:release, repository: @repository, tag_name: 'v1.10.0')

    assert_equal 1, (release1 <=> release2)
  end

  test 'backfill_immutability syncs GitHub repositories in bounded cursor batches' do
    github_host = create(:github_host)
    first_repository = create(:repository, host: github_host, full_name: 'actions/checkout')
    second_repository = create(:repository, host: github_host, full_name: 'actions/setup-node')
    create(:release, repository: first_repository, immutable: nil)
    create(:release, repository: second_repository, immutable: nil)

    known_repository = create(:repository, host: github_host, full_name: 'actions/known')
    create(:release, repository: known_repository, immutable: false)

    repository_names = [
      first_repository.full_name,
      second_repository.full_name.upcase,
      known_repository.full_name,
      'missing/action'
    ]
    expected_repository_ids = [first_repository.id, second_repository.id]
    open_transactions = []
    Host.any_instance.expects(:download_releases).twice.with do |repository|
      expected_repository_ids.delete(repository.id)
      open_transactions << Release.connection.open_transactions
      true
    end
    transaction_count = Release.connection.open_transactions

    processed, repositories_synced, repositories_missing, last_name, repositories_failed = Release.backfill_immutability(
      repository_names: repository_names,
      block_size: 1
    )

    assert_empty expected_repository_ids
    assert_equal [transaction_count, transaction_count], open_transactions
    assert_equal 4, processed
    assert_equal 2, repositories_synced
    assert_equal 1, repositories_missing
    assert_equal repository_names.sort_by(&:downcase).last, last_name
    assert_equal 0, repositories_failed
  end

  test 'backfill_immutability rejects an empty batch' do
    error = assert_raises(ArgumentError) do
      Release.backfill_immutability(repository_names: [], block_size: 0)
    end

    assert_equal 'block_size must be greater than zero', error.message
  end

  test 'backfill_immutability stops the release cursor after finding an unknown value' do
    github_host = mock('github_host')
    repository = mock('repository')
    releases = mock('releases')
    cursor = mock('cursor')
    Host.expects(:find_by_name).with('GitHub').returns(github_host)
    github_host.expects(:find_repository).with('actions/checkout').returns(repository)
    repository.expects(:releases).returns(releases)
    releases.expects(:select).with(:immutable).returns(cursor)
    cursor.expects(:each_row).with(block_size: 1_000, until: true).yields({ 'immutable' => nil })
    repository.expects(:download_releases)

    Release.backfill_immutability(repository_names: ['actions/checkout'])
  end

  test 'backfill_immutability continues after a GitHub server error' do
    github_host = create(:github_host)
    failing_repository = create(:repository, host: github_host, full_name: 'actions/failing')
    following_repository = create(:repository, host: github_host, full_name: 'actions/following')
    create(:release, repository: failing_repository, immutable: nil)
    create(:release, repository: following_repository, immutable: nil)
    error = Octokit::ServerError.new(status: 504, body: 'timeout')

    Host.stubs(:find_by_name).with('GitHub').returns(github_host)
    github_host.stubs(:find_repository).with(failing_repository.full_name).returns(failing_repository)
    github_host.stubs(:find_repository).with(following_repository.full_name).returns(following_repository)
    failing_repository.expects(:download_releases).raises(error)
    following_repository.expects(:download_releases)
    progress = []

    result = Release.backfill_immutability(
      repository_names: [failing_repository.full_name, following_repository.full_name]
    ) do |*values|
      progress << values
    end

    assert_equal [2, 1, 0, following_repository.full_name, 1], result
    assert_equal failing_repository.full_name, progress.first[3]
    assert_equal 1, progress.first[4]
    assert_equal error, progress.first[5]
  end
end
