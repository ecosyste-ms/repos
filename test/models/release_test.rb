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
    first_repository = create(:repository, host: github_host)
    second_repository = create(:repository, host: github_host)
    create(:release, repository: first_repository, immutable: nil)
    create(:release, repository: second_repository, immutable: nil)

    gitlab_repository = create(:gitlab_repository)
    create(:release, repository: gitlab_repository, immutable: nil)

    known_repository = create(:repository, host: github_host)
    create(:release, repository: known_repository, immutable: false)

    expected_repository_ids = [first_repository.id, second_repository.id]
    open_transactions = []
    Host.any_instance.expects(:download_releases).twice.with do |repository|
      expected_repository_ids.delete(repository.id)
      open_transactions << Release.connection.open_transactions
      true
    end
    transaction_count = Release.connection.open_transactions
    release_count = Release.count
    last_release_id = Release.maximum(:id)

    scanned, repositories_synced, last_id = Release.backfill_immutability(batch_size: 1)

    assert_empty expected_repository_ids
    assert_equal [transaction_count, transaction_count], open_transactions
    assert_equal release_count, scanned
    assert_equal 2, repositories_synced
    assert_equal last_release_id, last_id
  end

  test 'backfill_immutability rejects an empty batch' do
    error = assert_raises(ArgumentError) do
      Release.backfill_immutability(batch_size: 0)
    end

    assert_equal 'batch_size must be greater than zero', error.message
  end
end
