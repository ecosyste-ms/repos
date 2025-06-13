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

    test 'hidden scope returns only hidden owners' do
      assert_includes Owner.hidden, @hidden_owner
      assert_not_includes Owner.hidden, @visible_owner
      assert_not_includes Owner.hidden, @nil_owner
    end

    test 'visible scope returns non-hidden owners' do
      assert_includes Owner.visible, @visible_owner
      assert_includes Owner.visible, @nil_owner
      assert_not_includes Owner.visible, @hidden_owner
    end
  end
end
