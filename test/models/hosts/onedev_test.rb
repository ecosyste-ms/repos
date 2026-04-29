require "test_helper"

class Hosts::OnedevTest < ActiveSupport::TestCase
  setup do
    @host = create(:host, name: 'OneDev', url: 'https://code.onedev.io', kind: 'onedev')
    @onedev = Hosts::Onedev.new(@host)
  end

  should 'use onedev icon' do
    assert_equal 'onedev', @onedev.icon
  end

  should 'build OneDev file URLs' do
    repository = build(:repository, host: @host, full_name: 'onedev/server', default_branch: 'main')

    assert_equal 'https://code.onedev.io/onedev/server/~files/main/', @onedev.blob_url(repository)
    assert_equal 'https://code.onedev.io/onedev/server/~raw/main/', @onedev.raw_url(repository)
    assert_equal 'https://code.onedev.io/onedev/server/~files/v1.0.0', @onedev.tag_url(repository, 'v1.0.0')
  end

  should 'map project data from OneDev API' do
    @onedev.stubs(:fetch_source_path).with(7).returns('upstream/project')

    repo = @onedev.map_repository_data({
      'id' => 123,
      'path' => 'onedev/server',
      'description' => 'Self-hosted git server',
      'forkedFromId' => 7,
      'createDate' => '2026-01-01T00:00:00Z',
      'updateDate' => '2026-01-02T00:00:00Z',
      'defaultBranch' => 'main',
      'codeManagement' => true,
      'issueManagement' => true
    })

    assert_equal 123, repo[:uuid]
    assert_equal 'onedev/server', repo[:full_name]
    assert_equal 'onedev', repo[:owner]
    assert_equal 'Self-hosted git server', repo[:description]
    assert_equal true, repo[:fork]
    assert_equal 'main', repo[:default_branch]
    assert_equal true, repo[:has_issues]
    assert_equal true, repo[:pull_requests_enabled]
    assert_equal 'git', repo[:scm]
    assert_equal 'upstream/project', repo[:source_name]
    assert_equal [], repo[:topics]
  end
end
