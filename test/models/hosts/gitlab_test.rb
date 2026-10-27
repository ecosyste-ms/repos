require "test_helper"

class Hosts::GitlabTest < ActiveSupport::TestCase
  context 'anonymous first requests' do
    setup do
      @host = create(:host, name: 'gitlab.com', url: 'https://gitlab.com', kind: 'gitlab')
      Hosts::Gitlab.any_instance.stubs(:api_token).returns('test-token')
      @json = { 'Content-Type' => 'application/json' }
      @anonymous = ->(request) { !request.headers.key?('Private-Token') }
      @with_token = ->(request) { request.headers['Private-Token'] == 'test-token' }
    end

    should 'only use the token for a user profile gitlab refuses anonymously' do
      search = stub_request(:get, 'https://gitlab.com/api/v4/users?username=someone').with(&@anonymous)
        .to_return(status: 200, headers: @json, body: [{ id: 5, username: 'someone' }].to_json)
      refused = stub_request(:get, 'https://gitlab.com/api/v4/users/5').with(&@anonymous)
        .to_return(status: 403, headers: @json, body: { message: '403 Forbidden - Not authorized!' }.to_json)
      profile = stub_request(:get, 'https://gitlab.com/api/v4/users/5').with(&@with_token)
        .to_return(status: 200, headers: @json, body: { id: 5, username: 'someone', name: 'Some One', bio: 'Hello' }.to_json)
      projects = stub_request(:get, 'https://gitlab.com/api/v4/users/someone/projects?archived=false&per_page=100&simple=true').with(&@anonymous)
        .to_return(status: 200, headers: @json, body: [].to_json)

      SyncOwnerWorker.new.perform(@host.id, 'someone')

      assert_equal ['Some One', 'Hello'], @host.owners.find_by(login: 'someone').values_at(:name, :description)
      [search, refused, profile, projects].each { |stub| assert_requested stub, times: 1 }
    end

    should 'fall back to the token on a server that refuses anonymous requests' do
      project = { id: 9, path_with_namespace: 'group/project', name: 'project', description: 'A project', visibility: 'public',
                  created_at: '2020-01-01T00:00:00.000Z', last_activity_at: '2026-10-01T00:00:00.000Z', default_branch: 'main',
                  star_count: 1, avatar_url: nil, license: { key: 'mit' } }
      project_url = 'https://gitlab.com/api/v4/projects/group%2Fproject?license=true'
      refused = stub_request(:get, project_url).with(&@anonymous).to_return(status: 401, headers: @json, body: { message: '401 Unauthorized' }.to_json)
      stub_request(:get, project_url).with(&@with_token).to_return(status: 200, headers: @json, body: project.to_json)

      assert_equal 'group/project', @host.host_instance.fetch_repository('group/project')[:full_name]
      assert_requested refused, times: 1
    end
  end

  context 'hosts without a token' do
    setup do
      @host = create(:host, name: 'gitlab.example.org', url: 'https://gitlab.example.org', kind: 'gitlab')
      Hosts::Gitlab.any_instance.stubs(:api_token).returns(nil)
      @json = { 'Content-Type' => 'application/json' }
    end

    should 'not treat a missing project as data' do
      stub_request(:get, 'https://gitlab.example.org/api/v4/projects/group%2Fgone?license=true')
        .to_return(status: 404, headers: @json, body: { message: '404 Project Not Found' }.to_json)

      assert_nil @host.host_instance.fetch_repository('group/gone')
    end

    should 'not treat a refused user profile as data' do
      stub_request(:get, 'https://gitlab.example.org/api/v4/users?username=someone')
        .to_return(status: 200, headers: @json, body: [{ id: 5, username: 'someone' }].to_json)
      stub_request(:get, 'https://gitlab.example.org/api/v4/users/5')
        .to_return(status: 403, headers: @json, body: { message: '403 Forbidden - Not authorized!' }.to_json)

      assert_nil @host.host_instance.fetch_owner('someone')
    end

    should 'skip tags for a missing project' do
      repository = create(:repository, host: @host, full_name: 'group/gone')
      stub_request(:get, 'https://gitlab.example.org/api/v4/projects/group%2Fgone/repository/tags?search=&per_page=100&page=1')
        .to_return(status: 404, headers: @json, body: { message: '404 Project Not Found' }.to_json)

      repository.download_tags

      assert_empty repository.tags
    end
  end

  context 'token authenticated requests' do
    setup do
      @host = create(:host, name: 'gitlab.com', url: 'https://gitlab.com', kind: 'gitlab')
      Hosts::Gitlab.any_instance.stubs(:api_token).returns('test-token')
    end

    should 'sync an owner through the /api/v4 endpoints' do
      stub_request(:get, 'https://gitlab.com/api/v4/users?username=some-group')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: [].to_json)
      stub_request(:get, 'https://gitlab.com/api/v4/groups/some-group?with_projects=false')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { id: 7, path: 'some-group', name: 'Some Group' }.to_json)
      stub_request(:get, 'https://gitlab.com/api/v4/groups/some-group/projects?archived=false&include_subgroups=true&per_page=100&simple=true')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: [].to_json)

      SyncOwnerWorker.new.perform(@host.id, 'some-group')

      assert_equal 'Some Group', @host.owners.find_by(login: 'some-group').name
    end

    should 'sync a user owner' do
      stub_request(:get, 'https://gitlab.com/api/v4/users?username=someone')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: [{ id: 5, username: 'someone' }].to_json)
      stub_request(:get, 'https://gitlab.com/api/v4/users/5')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { id: 5, username: 'someone', name: 'Some One' }.to_json)
      stub_request(:get, 'https://gitlab.com/api/v4/users/someone/projects?archived=false&per_page=100&simple=true')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: [].to_json)

      SyncOwnerWorker.new.perform(@host.id, 'someone')

      owner = @host.owners.find_by(login: 'someone')
      assert_equal ['Some One', 'user'], [owner.name, owner.kind]
    end

    should 'download every page of tags' do
      repository = create(:repository, host: @host, full_name: 'group/project')
      tags_url = 'https://gitlab.com/api/v4/projects/group%2Fproject/repository/tags'
      tag = ->(name) { { name: name, commit: { id: "sha-#{name}", committed_date: '2026-10-01T00:00:00.000Z' } } }
      stub_request(:get, "#{tags_url}?per_page=100")
        .to_return(status: 200, body: [tag.('v2'), tag.('v1')].to_json,
                   headers: { 'Content-Type' => 'application/json', 'Link' => "<#{tags_url}?page=2&per_page=100>; rel=\"next\"" })
      stub_request(:get, "#{tags_url}?page=2&per_page=100")
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: [tag.('v0')].to_json)

      repository.download_tags

      assert_equal %w[v0 v1 v2], repository.tags.pluck(:name).sort
    end

    should 'queue every page of an owner repos' do
      projects_url = 'https://gitlab.com/api/v4/groups/some-group/projects'
      stub_request(:get, 'https://gitlab.com/api/v4/users?username=some-group')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: [].to_json)
      stub_request(:get, 'https://gitlab.com/api/v4/groups/some-group?with_projects=false')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { id: 7, path: 'some-group', name: 'Some Group' }.to_json)
      stub_request(:get, "#{projects_url}?archived=false&include_subgroups=true&per_page=100&simple=true")
        .to_return(status: 200, body: [{ path_with_namespace: 'some-group/a' }].to_json,
                   headers: { 'Content-Type' => 'application/json', 'Link' => "<#{projects_url}?page=2&per_page=100>; rel=\"next\"" })
      stub_request(:get, "#{projects_url}?page=2&per_page=100")
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: [{ path_with_namespace: 'some-group/b' }].to_json)
      Sidekiq::Worker.clear_all

      SyncOwnerWorker.new.perform(@host.id, 'some-group')

      assert_equal %w[some-group/a some-group/b], SyncRepositoryWorker.jobs.map { |job| job['args'].last }.sort
    end

    should 'stop listing owner repos after max_pages' do
      owner = create(:owner, host: @host, login: 'some-group', kind: 'organization')
      projects_url = 'https://gitlab.com/api/v4/groups/some-group/projects'
      stub_request(:get, "#{projects_url}?archived=false&include_subgroups=true&per_page=100&simple=true")
        .to_return(status: 200, body: [{ path_with_namespace: 'some-group/a' }].to_json,
                   headers: { 'Content-Type' => 'application/json', 'Link' => "<#{projects_url}?page=2&per_page=100>; rel=\"next\"" })

      assert_equal ['some-group/a'], @host.host_instance.load_owner_repos_names(owner, max_pages: 1)
    end
  end

  context 'rate limiting' do
    setup do
      @host = create(:host, name: 'gitlab.com', url: 'https://gitlab.com', kind: 'gitlab')
      Hosts::Gitlab.any_instance.stubs(:api_token).returns('test-token')
      @users_url = 'https://gitlab.com/api/v4/users?username=someone'
      stub_request(:get, @users_url).to_return(status: 429, headers: { 'Retry-After' => '3600' }, body: '{"message":"Retry later"}')
    end

    should 'raise a 429 from an owner sync without sleeping in the worker thread' do
      Gitlab::Request.any_instance.expects(:sleep).never

      assert_raises(Gitlab::Error::TooManyRequests) { SyncOwnerWorker.new.perform(@host.id, 'someone') }

      assert_requested :get, @users_url, times: 1
    end
  end

  context 'recently_changed_repo_names' do
    setup do
      @host = create(:host, url: 'https://gitlab.com', kind: 'gitlab')
      @gitlab_instance = Hosts::Gitlab.new(@host)
    end

    should 'handle empty array from load_repo_names' do
      @gitlab_instance.stubs(:load_repo_names).returns([])
      
      result = @gitlab_instance.recently_changed_repo_names
      
      assert_equal [], result
    end

    should 'handle nil entries in repos array' do
      repos_with_nil = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => 2.hours.ago },
        nil
      ]
      @gitlab_instance.stubs(:load_repo_names).returns(repos_with_nil)
      
      result = @gitlab_instance.recently_changed_repo_names
      
      assert_equal [], result
    end

    should 'return repo names and stop pagination when oldest is older than target' do
      recent_time = 30.minutes.ago
      old_time = 2.hours.ago
      
      first_page = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => recent_time },
        { "path_with_namespace" => "user/repo2", "last_activity_at" => recent_time }
      ]
      
      second_page = [
        { "path_with_namespace" => "user/repo3", "last_activity_at" => old_time }
      ]
      
      @gitlab_instance.stubs(:load_repo_names).with(1, "updated_at").returns(first_page)
      @gitlab_instance.stubs(:load_repo_names).with(2, "updated_at").returns(second_page)
      
      result = @gitlab_instance.recently_changed_repo_names(1.hour)
      
      assert_equal ["user/repo1", "user/repo2", "user/repo3"], result
    end

    should 'handle pagination correctly and stop on empty page' do
      recent_time = 30.minutes.ago
      older_time = 45.minutes.ago
      old_time = 2.hours.ago
      
      page1 = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => recent_time },
        { "path_with_namespace" => "user/repo2", "last_activity_at" => older_time }
      ]
      
      page2 = [
        { "path_with_namespace" => "user/repo3", "last_activity_at" => older_time },
        { "path_with_namespace" => "user/repo4", "last_activity_at" => old_time }
      ]
      
      @gitlab_instance.stubs(:load_repo_names).with(1, "updated_at").returns(page1)
      @gitlab_instance.stubs(:load_repo_names).with(2, "updated_at").returns(page2)
      
      result = @gitlab_instance.recently_changed_repo_names(1.hour)
      
      assert_equal ["user/repo1", "user/repo2", "user/repo3", "user/repo4"], result
    end

    should 'remove duplicate repo names' do
      recent_time = 30.minutes.ago
      old_time = 2.hours.ago
      
      page1 = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => recent_time },
        { "path_with_namespace" => "user/repo1", "last_activity_at" => recent_time }
      ]
      
      page2 = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => old_time }
      ]
      
      @gitlab_instance.stubs(:load_repo_names).with(1, "updated_at").returns(page1)
      @gitlab_instance.stubs(:load_repo_names).with(2, "updated_at").returns(page2)
      
      result = @gitlab_instance.recently_changed_repo_names
      
      assert_equal ["user/repo1"], result
    end
  end
end