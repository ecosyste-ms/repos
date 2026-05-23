require "test_helper"
require "rake"

class TakedownRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("takedown:hide_user")
    @host = create(:github_host)
  end

  teardown do
    ENV.delete('LOGIN')
    ENV.delete('HOST')
  end

  test "hide_user marks owner hidden and destroys repositories" do
    owner = create(:owner, host: @host, login: 'someuser', hidden: false)
    repo = create(:repository, host: @host, full_name: 'someuser/thing', owner: 'someuser')
    other = create(:repository, host: @host, full_name: 'other/thing', owner: 'other')

    ENV['LOGIN'] = 'someuser'
    capture_io { Rake::Task["takedown:hide_user"].execute }

    assert owner.reload.hidden?
    assert_nil Repository.find_by(id: repo.id)
    refute_nil Repository.find_by(id: other.id)
  end

  test "hide_user creates a hidden owner when none exists" do
    ENV['LOGIN'] = 'newuser'
    capture_io { Rake::Task["takedown:hide_user"].execute }

    owner = @host.owners.find_by('lower(login) = ?', 'newuser')
    refute_nil owner
    assert owner.hidden?
  end

  test "hide_user matches login case-insensitively" do
    owner = create(:owner, host: @host, login: 'MixedCase', hidden: false)
    create(:repository, host: @host, full_name: 'MixedCase/thing', owner: 'MixedCase')

    ENV['LOGIN'] = 'mixedcase'
    capture_io { Rake::Task["takedown:hide_user"].execute }

    assert owner.reload.hidden?
    assert_equal 0, @host.repositories.where(owner: 'MixedCase').count
  end

  test "hide_user aborts without LOGIN" do
    assert_raises(SystemExit) do
      capture_io { Rake::Task["takedown:hide_user"].execute }
    end
  end
end
