require "test_helper"

class TagTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository)
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
      @tag = Tag.create!(
        name: 'v1.0.0',
        sha: 'abc123',
        repository: @repository
      )
    end

    should 'generate correct purl for tag with version' do
      expected_purl = "pkg:github/rails/rails@v1.0.0"
      assert_equal expected_purl, @tag.purl
    end
  end
end
