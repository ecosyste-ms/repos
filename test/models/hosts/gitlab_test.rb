require "test_helper"

class Hosts::GitlabTest < ActiveSupport::TestCase
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