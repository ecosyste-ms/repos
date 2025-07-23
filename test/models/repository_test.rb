require "test_helper"

class RepositoryTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:host)
    should have_many(:manifests)
    should have_many(:tags)
  end

  context 'purl method' do
    setup do
      @host = Host.create!(name: 'GitHub', url: 'https://github.com', kind: 'github')
      @repository = Repository.create!(
        full_name: 'rails/rails',
        owner: 'rails',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
    end

    should 'generate correct purl for github repository' do
      expected_purl = "pkg:github/rails/rails"
      assert_equal expected_purl, @repository.purl
    end
  end

  context 'owner_hidden? method' do
    setup do
      @host = Host.create!(name: 'GitHub', url: 'https://github.com', kind: 'github')
      @visible_owner = Owner.create!(login: 'visible', host: @host, hidden: false)
      @hidden_owner = Owner.create!(login: 'hidden', host: @host, hidden: true)
      @nil_owner = Owner.create!(login: 'nil-owner', host: @host, hidden: nil)
    end

    should 'return false for repository with visible owner' do
      repository = Repository.create!(
        full_name: 'visible/repo',
        owner: 'visible',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal false, repository.owner_hidden?
    end

    should 'return true for repository with hidden owner' do
      repository = Repository.create!(
        full_name: 'hidden/repo',
        owner: 'hidden',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal true, repository.owner_hidden?
    end

    should 'return false for repository with nil hidden owner' do
      repository = Repository.create!(
        full_name: 'nil-owner/repo',
        owner: 'nil-owner',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal false, repository.owner_hidden?
    end

    should 'return false for repository with no owner' do
      repository = Repository.create!(
        full_name: 'no/owner',
        owner: '',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal false, repository.owner_hidden?
    end

    should 'return false for repository with nonexistent owner' do
      repository = Repository.create!(
        full_name: 'nonexistent/repo',
        owner: 'nonexistent',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal false, repository.owner_hidden?
    end
  end

  context 'sync method' do
    should 'return early if host is nil' do
      repository = Repository.new(
        full_name: 'test/repo',
        owner: 'test',
        uuid: '456',
        host: nil,
        created_at: Time.now,
        updated_at: Time.now
      )
      
      assert_nil repository.sync
    end
  end
end
