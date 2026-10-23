require "test_helper"
require "rake"

class DependenciesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('dependencies:backfill_tag_repository_ids')
    Rake::Task['dependencies:backfill_tag_repository_ids'].reenable
  end

  def tag_dependency(repository_id:, tag: create(:tag))
    manifest = create(:manifest, repository: nil, tag: tag)
    dependency = create(:dependency, manifest: manifest)
    dependency.update_columns(repository_id: repository_id, updated_at: 1.day.ago)
    dependency
  end

  test 'backfill_tag_repository_ids points tag dependencies at the repository of their tag' do
    tag = create(:tag)
    wrong = tag_dependency(repository_id: tag.id + 1_000, tag: tag)
    correct = tag_dependency(repository_id: tag.repository_id, tag: tag)
    unchanged_updated_at = correct.reload.updated_at

    output = capture_io do
      Rake::Task['dependencies:backfill_tag_repository_ids'].invoke
    end.first

    assert_equal tag.repository_id, wrong.reload.repository_id
    assert_operator wrong.updated_at, :>, 1.hour.ago
    assert_equal unchanged_updated_at, correct.reload.updated_at
    assert_includes output, 'Done: processed 2 manifests in 1 batches, updated 1 dependencies'
  end

  test 'backfill_tag_repository_ids leaves repository manifests alone' do
    repository_manifest = create(:manifest)
    dependency = create(:dependency, manifest: repository_manifest)
    dependency.update_columns(repository_id: repository_manifest.repository_id + 1_000)

    capture_io { Rake::Task['dependencies:backfill_tag_repository_ids'].invoke }

    assert_equal repository_manifest.repository_id + 1_000, dependency.reload.repository_id
  end

  test 'backfill_tag_repository_ids skips manifests whose tag no longer exists' do
    tag = create(:tag)
    orphan = tag_dependency(repository_id: 42, tag: tag)
    Tag.where(id: tag.id).delete_all

    output = capture_io do
      Rake::Task['dependencies:backfill_tag_repository_ids'].invoke
    end.first

    assert_equal 42, orphan.reload.repository_id
    assert_includes output, 'updated 0 dependencies'
  end

  test 'backfill_tag_repository_ids works in batches and resumes after the given manifest id' do
    first = tag_dependency(repository_id: 0)
    second = tag_dependency(repository_id: 0)
    third = tag_dependency(repository_id: 0)

    output = capture_io do
      Rake::Task['dependencies:backfill_tag_repository_ids'].invoke(1, first.manifest_id)
    end.first

    assert_equal 0, first.reload.repository_id
    assert_equal second.manifest.tag.repository_id, second.reload.repository_id
    assert_equal third.manifest.tag.repository_id, third.reload.repository_id
    assert_includes output, "Processed 1 batches, updated 1 dependencies, last manifest id #{second.manifest_id}"
    assert_includes output, "Done: processed 2 manifests in 2 batches, updated 2 dependencies, last manifest id #{third.manifest_id}"
  end

  test 'backfill_tag_repository_ids lifts the statement timeout for each batch update' do
    tag_dependency(repository_id: 0)
    tag_dependency(repository_id: 0)
    statements = []
    callback = lambda do |*, payload|
      statements << :timeout if payload[:sql].include?('SET LOCAL statement_timeout = 0')
      statements << :update if payload[:sql].start_with?('UPDATE dependencies')
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      capture_io { Rake::Task['dependencies:backfill_tag_repository_ids'].invoke(1) }
    end

    assert_equal [:timeout, :update, :timeout, :update], statements
  end

  test 'backfill_tag_repository_ids rejects an empty batch' do
    _output, errors = capture_io do
      assert_raises(SystemExit) { Rake::Task['dependencies:backfill_tag_repository_ids'].invoke(0) }
    end

    assert_includes errors, 'batch_size must be greater than zero'
  end
end
