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
end
