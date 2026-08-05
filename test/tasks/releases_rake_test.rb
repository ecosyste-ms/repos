require 'test_helper'
require 'rake'

class ReleasesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('releases:backfill_immutability')
    Rake::Task['releases:backfill_immutability'].reenable
  end

  test 'backfill_immutability passes batch and resume arguments' do
    Release.expects(:backfill_immutability)
      .with(batch_size: 250, after_id: 1_000)
      .yields(250, 20, 1_250)
      .returns([250, 20, 1_250])

    output = capture_io do
      Rake::Task['releases:backfill_immutability'].invoke(250, 1_000)
    end.first

    assert_includes output, 'last id 1250'
  end
end
