require "test_helper"

class GogsTest < ActiveSupport::TestCase
  setup do
    @host = Host.new(name: 'Gogs', url: 'https://notabug.org', kind: 'gogs')
    @gogs = Hosts::Gogs.new(@host)
  end

  test 'uses gogs icon' do
    assert_equal 'gogs', @gogs.icon
  end

  test 'inherits gitea repository mapping without topics' do
    data = {
      'id' => 123,
      'full_name' => 'hp/gogs',
      'owner' => { 'login' => 'hp', 'avatar_url' => 'https://notabug.org/avatars/hp' },
      'language' => 'Go',
      'archived' => false,
      'fork' => false,
      'description' => 'Gogs mirror',
      'size' => 42,
      'stars_count' => 7,
      'open_issues_count' => 1,
      'forks_count' => 2,
      'default_branch' => 'master',
      'website' => 'https://gogs.io',
      'has_issues' => true,
      'has_wiki' => true,
      'mirror' => false,
      'private' => false,
      'has_pull_requests' => true,
      'avatar_url' => nil,
      'created_at' => '2026-01-01T00:00:00Z',
      'updated_at' => '2026-01-02T00:00:00Z'
    }

    mapped = @gogs.map_repository_data(data)

    assert_equal 123, mapped[:uuid]
    assert_equal 'hp/gogs', mapped[:full_name]
    assert_equal 'hp', mapped[:owner]
    assert_equal 'git', mapped[:scm]
    assert_equal [], mapped[:topics]
    assert_equal 'https://notabug.org/avatars/hp', mapped[:logo_url]
  end

  test 'does not expose unsupported topic URLs' do
    assert_nil @gogs.topic_url('ruby')
  end
end
