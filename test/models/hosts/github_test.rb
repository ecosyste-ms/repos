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

      result = @github.fetch_releases(@repository)

      assert_equal 1, result.length
      assert_equal 1, result.first[:uuid]
      assert_equal 'v1.0.0', result.first[:tag_name]
    end

    should 'stop after max_pages' do
      release1 = OpenStruct.new(
        id: 1, tag_name: 'v1.0', target_commitish: 'main', name: 'r', body: 'b',
        draft: false, prerelease: false, created_at: Time.now, published_at: Time.now,
        author: OpenStruct.new(login: 'u'), assets: []
      )
      release2 = OpenStruct.new(
        id: 2, tag_name: 'v2.0', target_commitish: 'main', name: 'r2', body: 'b2',
        draft: false, prerelease: false, created_at: Time.now, published_at: Time.now,
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

      result = @github.fetch_releases(@repository, max_pages: 2)

      assert_equal 2, result.length
      assert_equal 'v1.0', result.first[:tag_name]
      assert_equal 'v2.0', result.last[:tag_name]
    end

    should 'return empty array on error' do
      client = mock('client')
      client.expects(:releases).raises(Octokit::NotFound)
      @github.stubs(:api_client).with(nil, auto_paginate: false).returns(client)

      result = @github.fetch_releases(@repository)

      assert_equal [], result
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

      result = @github.fetch_tags(@repository)

      assert_equal 1, result.length
      assert_equal 'v1.0.0', result.first[:name]
      assert_equal 'sha1', result.first[:sha]
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

      result = @github.fetch_tags(@repository, max_pages: 2)

      assert_equal 2, result.length
      assert_equal 'v1.0', result.first[:name]
      assert_equal 'v2.0', result.last[:name]
    end

    should 'return nil when graphql returns no data' do
      @github.expects(:fetch_tags_graphql).with(@repository).returns({ data: nil })

      result = @github.fetch_tags(@repository)

      assert_nil result
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
