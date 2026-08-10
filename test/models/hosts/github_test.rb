require "test_helper"

class Hosts::GithubTest < ActiveSupport::TestCase
  setup do
    @host = create(:github_host)
    @github = Hosts::Github.new(@host)
    @repository = create(:repository, host: @host, full_name: 'testuser/testrepo', owner: 'testuser')
  end

  context 'fetch_releases' do
    should 'fetch releases with manual pagination' do
      release = OpenStruct.new(
        id: 1,
        tag_name: 'v1.0.0',
        target_commitish: 'main',
        name: 'Release 1.0.0',
        body: 'First release',
        draft: false,
        prerelease: false,
        immutable: true,
        created_at: 1.day.ago,
        published_at: 1.day.ago,
        author: OpenStruct.new(login: 'testuser'),
        assets: []
      )

      last_response = mock('last_response')
      last_response.stubs(:rels).returns({})

      client = mock('client')
      client.expects(:releases).with('testuser/testrepo', per_page: 100).returns([release])
      client.stubs(:last_response).returns(last_response)

      @github.stubs(:api_client).with(nil, auto_paginate: false).returns(client)

      result, complete = @github.fetch_releases(@repository)

      assert_equal 1, result.length
      assert_equal 1, result.first[:uuid]
      assert_equal 'v1.0.0', result.first[:tag_name]
      assert result.first[:immutable]
      assert complete
    end

    should 'stop after max_pages' do
      release1 = OpenStruct.new(
        id: 1, tag_name: 'v1.0', target_commitish: 'main', name: 'r', body: 'b',
        draft: false, prerelease: false, immutable: false, created_at: Time.now, published_at: Time.now,
        author: OpenStruct.new(login: 'u'), assets: []
      )
      release2 = OpenStruct.new(
        id: 2, tag_name: 'v2.0', target_commitish: 'main', name: 'r2', body: 'b2',
        draft: false, prerelease: false, immutable: true, created_at: Time.now, published_at: Time.now,
        author: OpenStruct.new(login: 'u'), assets: []
      )

      page2_response = mock('page2_response')
      page2_response.stubs(:data).returns([release2])
      page2_response.stubs(:rels).returns({})

      next_rel = mock('next_rel')
      next_rel.stubs(:get).returns(page2_response)

      first_last_response = mock('first_last_response')
      first_last_response.stubs(:rels).returns({ next: next_rel })

      client = mock('client')
      client.expects(:releases).with('testuser/testrepo', per_page: 100).returns([release1])
      client.stubs(:last_response).returns(first_last_response)

      @github.stubs(:api_client).with(nil, auto_paginate: false).returns(client)

      result, complete = @github.fetch_releases(@repository, max_pages: 2)

      assert_equal 2, result.length
      assert_equal 'v1.0', result.first[:tag_name]
      assert_equal 'v2.0', result.last[:tag_name]
      assert complete
    end

    should 'report incomplete when max_pages leaves a next link' do
      release = OpenStruct.new(
        id: 1, tag_name: 'v1.0', target_commitish: 'main', name: 'r', body: 'b',
        draft: false, prerelease: false, immutable: false, created_at: Time.now, published_at: Time.now,
        author: OpenStruct.new(login: 'u'), assets: []
      )
      next_rel = mock('next_rel')
      last_response = mock('last_response')
      last_response.stubs(:rels).returns({ next: next_rel })
      client = mock('client')
      client.expects(:releases).with('testuser/testrepo', per_page: 100).returns([release])
      client.stubs(:last_response).returns(last_response)
      @github.stubs(:api_client).with(nil, auto_paginate: false).returns(client)

      result, complete = @github.fetch_releases(@repository, max_pages: 1)

      assert_equal 1, result.length
      assert_not complete
    end

    should 'return empty array on error' do
      client = mock('client')
      client.expects(:releases).raises(Octokit::NotFound)
      @github.stubs(:api_client).with(nil, auto_paginate: false).returns(client)

      result, complete = @github.fetch_releases(@repository)

      assert_equal [], result
      assert_not complete
    end
  end

  context 'download_releases' do
    should 'store immutability for new releases and refresh existing releases' do
      existing_release = create(
        :release,
        repository: @repository,
        uuid: '1',
        tag_name: 'v1.0.0',
        immutable: false,
        last_synced_at: 2.days.ago
      )
      unchanged_updated_at = 2.days.ago.change(usec: 0)
      unchanged_release = create(
        :release,
        repository: @repository,
        uuid: '2',
        tag_name: 'v2.0.0',
        immutable: false,
        updated_at: unchanged_updated_at
      )

      @github.stubs(:fetch_releases).with(@repository).returns([[
        { uuid: 1, tag_name: 'v1.0.0', immutable: true, last_synced_at: Time.current },
        { uuid: 2, tag_name: 'v2.0.0', immutable: false, last_synced_at: Time.current },
        { uuid: 3, tag_name: 'v3.0.0', immutable: false, last_synced_at: Time.current }
      ], true])

      @github.download_releases(@repository)

      assert_equal 3, @repository.releases.count
      assert existing_release.reload.immutable
      assert_not @repository.releases.find_by!(uuid: '3').immutable
      assert_operator existing_release.last_synced_at, :>, 2.days.ago
      assert_equal unchanged_updated_at, unchanged_release.reload.updated_at
    end

    should 'delete releases GitHub no longer returns when the fetch is complete' do
      kept = create(:release, repository: @repository, uuid: '1', tag_name: 'v2', immutable: false)
      orphan = create(:release, repository: @repository, uuid: '99', tag_name: 'v2', immutable: nil)

      @github.stubs(:fetch_releases).with(@repository).returns([[
        { uuid: 1, tag_name: 'v2', immutable: false, last_synced_at: Time.current }
      ], true])

      @github.download_releases(@repository)

      assert Release.exists?(kept.id)
      assert_not Release.exists?(orphan.id)
      assert_equal 1, @repository.releases.count
    end

    should 'keep releases GitHub did not return when the fetch was truncated' do
      kept = create(:release, repository: @repository, uuid: '1', tag_name: 'v1')
      beyond_page_cap = create(:release, repository: @repository, uuid: '99', tag_name: 'v0.1')

      @github.stubs(:fetch_releases).with(@repository).returns([[
        { uuid: 1, tag_name: 'v1', immutable: false, last_synced_at: Time.current }
      ], false])

      @github.download_releases(@repository)

      assert Release.exists?(kept.id)
      assert Release.exists?(beyond_page_cap.id)
    end
  end

  context 'fetch_tags' do
    should 'fetch tags via graphql' do
      graphql_response = {
        data: {
          repository: {
            refs: {
              pageInfo: { startCursor: 'abc', hasNextPage: false, endCursor: 'def' },
              nodes: [
                { name: 'v1.0.0', target: { __typename: 'Commit', oid: 'sha1', committer: { date: '2026-01-01' } } }
              ]
            }
          }
        }
      }

      @github.expects(:fetch_tags_graphql).with(@repository).returns(graphql_response)

      result, complete = @github.fetch_tags(@repository)

      assert_equal 1, result.length
      assert_equal 'v1.0.0', result.first[:name]
      assert_equal 'sha1', result.first[:sha]
      assert complete
    end

    should 'stop after max_pages' do
      page1_response = {
        data: {
          repository: {
            refs: {
              pageInfo: { startCursor: 'a', hasNextPage: true, endCursor: 'cursor1' },
              nodes: [
                { name: 'v1.0', target: { __typename: 'Commit', oid: 'sha1', committer: { date: '2026-01-01' } } }
              ]
            }
          }
        }
      }

      page2_response = {
        data: {
          repository: {
            refs: {
              pageInfo: { startCursor: 'b', hasNextPage: true, endCursor: 'cursor2' },
              nodes: [
                { name: 'v2.0', target: { __typename: 'Commit', oid: 'sha2', committer: { date: '2026-01-02' } } }
              ]
            }
          }
        }
      }

      @github.expects(:fetch_tags_graphql).with(@repository).returns(page1_response)
      @github.expects(:fetch_tags_graphql).with(@repository, 'cursor1').returns(page2_response)

      result, complete = @github.fetch_tags(@repository, max_pages: 2)

      assert_equal 2, result.length
      assert_equal 'v1.0', result.first[:name]
      assert_equal 'v2.0', result.last[:name]
      assert_not complete
    end

    should 'return nil when graphql returns no data' do
      @github.expects(:fetch_tags_graphql).with(@repository).returns({ data: nil })

      result, complete = @github.fetch_tags(@repository)

      assert_nil result
      assert_not complete
    end
  end

  context 'download_tags' do
    should 'update moved tags, delete orphans and insert new tags when the fetch is complete' do
      moved = create(:tag, repository: @repository, name: 'v2', sha: 'oldsha', dependencies_parsed_at: 1.day.ago, dependency_job_id: 'job')
      kept_manifest = create(:manifest, repository: nil, tag: moved)
      orphan = create(:tag, repository: @repository, name: 'gone', sha: 'deadsha')
      orphan_manifest = create(:manifest, repository: nil, tag: orphan)
      orphan_dependency = create(:dependency, repository: @repository, manifest: orphan_manifest)
      @repository.update_columns(tags_count: 2)

      @github.stubs(:fetch_tags).with(@repository).returns([[
        { name: 'v2', sha: 'newsha', kind: 'commit', published_at: Time.current },
        { name: 'v2.1', sha: 'abc', kind: 'commit', published_at: Time.current }
      ], true])

      @github.download_tags(@repository)

      moved.reload
      assert_equal 'newsha', moved.sha
      assert_nil moved.dependencies_parsed_at
      assert_nil moved.dependency_job_id
      assert Manifest.exists?(kept_manifest.id)
      assert_not Tag.exists?(orphan.id)
      assert_not Manifest.exists?(orphan_manifest.id)
      assert_not Dependency.exists?(orphan_dependency.id)
      assert @repository.tags.exists?(name: 'v2.1')
      assert_equal 2, @repository.reload.tags_count
    end

    should 'keep tags GitHub did not return when the fetch was truncated' do
      beyond_page_cap = create(:tag, repository: @repository, name: 'v0.0.1', sha: 'oldsha')

      @github.stubs(:fetch_tags).with(@repository).returns([[
        { name: 'v2', sha: 'abc', kind: 'commit', published_at: Time.current }
      ], false])

      @github.download_tags(@repository)

      assert Tag.exists?(beyond_page_cap.id)
      assert_equal 2, @repository.reload.tags_count
    end
  end

  context 'load_owner_repos_names' do
    setup do
      @owner = OpenStruct.new(login: 'testuser')
    end

    should 'fetch repo names with manual pagination' do
      repo = { full_name: 'testuser/repo1' }

      last_response = mock('last_response')
      last_response.stubs(:rels).returns({})

      client = mock('client')
      client.expects(:repos).with('testuser', type: 'all', per_page: 100).returns([repo])
      client.stubs(:last_response).returns(last_response)

      @github.stubs(:api_client).with(nil, auto_paginate: false).returns(client)

      result = @github.load_owner_repos_names(@owner)

      assert_equal ['testuser/repo1'], result
    end

    should 'stop after max_pages' do
      repo1 = { full_name: 'testuser/repo1' }
      repo2 = { full_name: 'testuser/repo2' }

      page2_response = mock('page2_response')
      page2_response.stubs(:data).returns([repo2])
      page2_response.stubs(:rels).returns({})

      next_rel = mock('next_rel')
      next_rel.stubs(:get).returns(page2_response)

      first_last_response = mock('first_last_response')
      first_last_response.stubs(:rels).returns({ next: next_rel })

      client = mock('client')
      client.expects(:repos).with('testuser', type: 'all', per_page: 100).returns([repo1])
      client.stubs(:last_response).returns(first_last_response)

      @github.stubs(:api_client).with(nil, auto_paginate: false).returns(client)

      result = @github.load_owner_repos_names(@owner, max_pages: 2)

      assert_equal ['testuser/repo1', 'testuser/repo2'], result
    end

    should 'return empty array on error' do
      client = mock('client')
      client.expects(:repos).raises(Octokit::NotFound)
      @github.stubs(:api_client).with(nil, auto_paginate: false).returns(client)

      result = @github.load_owner_repos_names(@owner)

      assert_equal [], result
    end
  end
end
