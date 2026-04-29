require 'test_helper'

class PingOwnerRepositoriesWorkerTest < ActiveSupport::TestCase
  setup do
    @host = create(:host, name: 'GitLab', url: 'https://gitlab.com', kind: 'gitlab')
    @owner = @host.owners.create!(login: 'public-group', kind: :organization)
  end

  test 'syncs repositories for existing owner' do
    Host.expects(:find_by_name).with('GitLab').returns(@host)
    @owner.expects(:sync_repositories)

    PingOwnerRepositoriesWorker.new.perform('GitLab', 'public-group')
  end

  test 'creates owner before syncing repositories when missing' do
    new_owner = build(:owner, host: @host, login: 'new-group', kind: :organization)
    Host.expects(:find_by_name).with('GitLab').returns(@host)
    @host.expects(:sync_owner).with('new-group').returns(new_owner)
    new_owner.expects(:sync_repositories)

    PingOwnerRepositoriesWorker.new.perform('GitLab', 'new-group')
  end
end
