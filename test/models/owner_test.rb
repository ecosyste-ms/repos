require "test_helper"

class OwnerTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:host)
  end

  context 'scopes' do
    setup do
      @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
      @visible_owner = Owner.create(login: 'visible', host: @host, hidden: false)
      @hidden_owner = Owner.create(login: 'hidden', host: @host, hidden: true)
      @nil_owner = Owner.create(login: 'nil', host: @host, hidden: nil)
    end

    should 'return only hidden owners for hidden scope' do
      assert_includes Owner.hidden, @hidden_owner
      assert_not_includes Owner.hidden, @visible_owner
      assert_not_includes Owner.hidden, @nil_owner
    end

    should 'return non-hidden owners for visible scope' do
      assert_includes Owner.visible, @visible_owner
      assert_includes Owner.visible, @nil_owner
      assert_not_includes Owner.visible, @hidden_owner
    end
  end

  context 'sync methods' do
    setup do
      @host = FactoryBot.create(:github_host)
      @visible_owner = FactoryBot.create(:owner, host: @host, hidden: false)
      @hidden_owner = FactoryBot.create(:hidden_owner, host: @host)
    end

    should 'not sync repositories for hidden owners' do
      @host.expects(:sync_owner_repositories_async).never
      @hidden_owner.sync_repositories
    end

    should 'sync repositories for visible owners' do
      @host.expects(:sync_owner_repositories_async).with(@visible_owner).once
      @visible_owner.sync_repositories
    end

    should 'not call host.sync_owner for hidden owners' do
      @host.expects(:sync_owner).never
      result = @hidden_owner.sync
      assert_equal @hidden_owner, result
    end

    should 'call host.sync_owner for visible owners' do
      @host.expects(:sync_owner).with(@visible_owner.login).once
      @visible_owner.sync
    end
  end
end
