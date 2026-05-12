require "test_helper"

class CronTaskWorkerTest < ActiveSupport::TestCase
  test "runs allowed rake task" do
    task_name = "repositories:sync_least_recent"
    task = mock

    Rake::Task.expects(:task_defined?).with(task_name).returns(true)
    Rake::Task.expects(:[]).with(task_name).returns(task)
    task.expects(:reenable)
    task.expects(:invoke)

    CronTaskWorker.new.perform(task_name)
  end

  test "rejects unknown rake task" do
    error = assert_raises(ArgumentError) do
      CronTaskWorker.new.perform("db:drop")
    end

    assert_equal "Unsupported cron task: db:drop", error.message
  end
end
