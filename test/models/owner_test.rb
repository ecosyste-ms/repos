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

  context 'funding' do
    setup do
      @host = FactoryBot.create(:github_host)
      @owner = FactoryBot.create(:owner, host: @host, login: 'acme', metadata: {})
    end

    should 'return sponsors link when has_sponsors_listing and no funding metadata' do
      @owner.metadata['has_sponsors_listing'] = true
      assert_equal ['https://github.com/sponsors/acme'], @owner.funding_links
    end

    should 'return empty when no sponsors listing and no funding metadata' do
      assert_equal [], @owner.funding_links
    end

    should 'map funding metadata to urls without querying repositories' do
      @owner.metadata['funding'] = { 'github' => ['acme'], 'open_collective' => 'acme' }
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        links = @owner.funding_links
        assert_includes links, 'https://github.com/sponsors/acme'
        assert_includes links, 'https://opencollective.com/acme'
      end
      assert_equal 0, queries
    end

    should 'fetch_funding reads from related .github repo' do
      FactoryBot.create(:repository, host: @host, full_name: 'acme/.github', owner: 'acme',
                        metadata: { 'funding' => { 'github' => ['acme'] } })
      assert_equal({ 'github' => ['acme'] }, @owner.fetch_funding)
    end

    should 'fetch_funding returns nil when no .github repo' do
      assert_nil @owner.fetch_funding
    end

    should 'update_funding persists funding into metadata' do
      FactoryBot.create(:repository, host: @host, full_name: 'acme/.github', owner: 'acme',
                        metadata: { 'funding' => { 'ko_fi' => 'acme' } })
      @owner.update_funding
      assert_equal({ 'ko_fi' => 'acme' }, @owner.reload.metadata['funding'])
    end

    should 'update_funding is a no-op when funding unchanged' do
      @owner.update_column(:metadata, { 'funding' => nil })
      @owner.expects(:update_column).never
      @owner.update_funding
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
