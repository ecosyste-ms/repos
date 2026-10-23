require 'test_helper'

class PingOwnerWorkerTest < ActiveSupport::TestCase
  setup do
    @host = FactoryBot.create(:github_host)
    @owner = FactoryBot.create(:owner, host: @host, login: 'testorg')
  end

  test 'syncs existing owner and repings its repositories' do
    Owner.any_instance.expects(:sync_async).with(false).once
    Owner.any_instance.expects(:reping_repositories_async).with(false).once

    PingOwnerWorker.new.perform(@host.name, 'testorg')
  end

  test 'supports force flag for existing owner' do
    Owner.any_instance.expects(:sync_async).with(true).once
    Owner.any_instance.expects(:reping_repositories_async).with(true).once

    PingOwnerWorker.new.perform(@host.name, 'testorg', true)
  end

  test 'discovers and creates missing owner then repings repositories' do
    new_owner = FactoryBot.build(:owner, host: @host, login: 'neworg')
    Host.any_instance.expects(:sync_owner).with('neworg', force: false).returns(new_owner)
    new_owner.expects(:reping_repositories_async).with(false).once

    PingOwnerWorker.new.perform(@host.name, 'neworg')
  end
end
