require "test_helper"

class Hosts::GogsTest < ActiveSupport::TestCase
  setup do
    @host = create(:host, name: 'Gogs', url: 'https://try.gogs.io', kind: 'gogs')
    @gogs = Hosts::Gogs.new(@host)
  end

  should 'use gogs icon' do
    assert_equal 'gogs', @gogs.icon
  end

  should 'map repository data using the Gitea-compatible API shape' do
    data = {
      'id' => 123,
      'full_name' => 'gogs/gogs',
      'owner' => { 'login' => 'gogs', 'avatar_url' => 'https://try.gogs.io/avatars/1' },
      'language' => 'Go',
      'archived' => false,
      'fork' => false,
      'description' => 'Gogs repository',
      'size' => 42,
      'stars_count' => 100,
      'open_issues_count' => 2,
      'forks_count' => 3,
      'default_branch' => 'main',
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

    repo = @gogs.map_repository_data(data)

    assert_equal 123, repo[:uuid]
    assert_equal 'gogs/gogs', repo[:full_name]
    assert_equal 'gogs', repo[:owner]
    assert_equal 'Go', repo[:language]
    assert_equal 'git', repo[:scm]
    assert_equal true, repo[:pull_requests_enabled]
    assert_equal [], repo[:topics]
    assert_equal 'https://try.gogs.io/avatars/1', repo[:logo_url]
  end
end
