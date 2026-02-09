require "test_helper"

class HostTest < ActiveSupport::TestCase
  context 'find_by_name methods' do
    setup do
      @host = create(:host, name: 'GitHub', url: 'https://github.com')
    end

    should 'find host by name' do
      found = Host.find_by_name('GitHub')
      assert_equal @host, found
    end

    should 'find host by name case insensitively' do
      found = Host.find_by_name('github')
      assert_equal @host, found
    end

    should 'find host by domain when name not found' do
      found = Host.find_by_name('github.com')
      assert_equal @host, found
    end

    should 'return nil for find_by_name with unknown name' do
      found = Host.find_by_name('unknown')
      assert_nil found
    end

    should 'find host by domain case insensitively' do
      found = Host.find_by_domain('GITHUB.COM')
      assert_equal @host, found
    end

    should 'find host by domain with trailing slash' do
      found = Host.find_by_domain('github.com/')
      assert_equal @host, found
    end

    should 'find host by domain from full URL' do
      found = Host.find_by_domain('https://github.com/')
      assert_equal @host, found
    end

    should 'find host by domain with path components' do
      found = Host.find_by_domain('github.com/some/path')
      assert_equal @host, found
    end

    should 'return nil for find_by_domain with blank input' do
      assert_nil Host.find_by_domain(nil)
      assert_nil Host.find_by_domain('')
      assert_nil Host.find_by_domain('   ')
    end

    should 'return nil for find_by_domain with invalid URL' do
      assert_nil Host.find_by_domain('://invalid')
    end

    should 'find host by name with bang method' do
      found = Host.find_by_name!('GitHub')
      assert_equal @host, found
    end

    should 'find host by domain with bang method' do
      found = Host.find_by_name!('github.com')
      assert_equal @host, found
    end

    should 'raise RecordNotFound for unknown name with bang method' do
      assert_raises(ActiveRecord::RecordNotFound) do
        Host.find_by_name!('unknown')
      end
    end
  end

  context 'associations' do
    should have_many(:repositories)
    should have_many(:owners)

    should 'destroy repositories when host is destroyed' do
      host = create(:host)
      repo1 = create(:repository, host: host)
      repo2 = create(:repository, host: host)
      
      assert_equal 2, host.repositories.count
      
      host.destroy
      
      assert_raises(ActiveRecord::RecordNotFound) { repo1.reload }
      assert_raises(ActiveRecord::RecordNotFound) { repo2.reload }
    end

    should 'destroy owners when host is destroyed' do
      host = create(:host)
      owner1 = create(:owner, host: host)
      owner2 = create(:owner, host: host)
      
      assert_equal 2, host.owners.count
      
      host.destroy
      
      assert_raises(ActiveRecord::RecordNotFound) { owner1.reload }
      assert_raises(ActiveRecord::RecordNotFound) { owner2.reload }
    end
  end

  context 'robots.txt functionality' do
    setup do
      @host = create(:host, url: 'https://example.com')
    end

    should 'return correct robots_txt_url' do
      assert_equal 'https://example.com/robots.txt', @host.robots_txt_url
    end

    should 'handle trailing slash in robots_txt_url' do
      @host.update(url: 'https://example.com/')
      assert_equal 'https://example.com/robots.txt', @host.robots_txt_url
    end

    should 'return true for robots_txt_stale? when never fetched' do
      assert @host.robots_txt_stale?
    end

    should 'return false for robots_txt_stale? when recently fetched' do
      @host.update(robots_txt_updated_at: 1.hour.ago)
      assert_not @host.robots_txt_stale?
    end

    should 'return true for robots_txt_stale? when old' do
      @host.update(robots_txt_updated_at: 2.days.ago)
      assert @host.robots_txt_stale?
    end

    should 'return true for can_crawl? when no robots.txt content' do
      assert @host.can_crawl?('/any/path')
    end

    should 'respect disallow rules in can_crawl?' do
      robots_content = <<~ROBOTS
        User-agent: *
        Disallow: /private/
        Disallow: /admin
      ROBOTS
      
      @host.update(robots_txt_content: robots_content)
      
      assert_not @host.can_crawl?('/private/file.txt')
      assert_not @host.can_crawl?('/admin')
      assert @host.can_crawl?('/public/file.txt')
    end

    should 'respect allow rules that override disallow in can_crawl?' do
      robots_content = <<~ROBOTS
        User-agent: *
        Disallow: /private/
        Allow: /private/allowed/
      ROBOTS
      
      @host.update(robots_txt_content: robots_content)
      
      assert_not @host.can_crawl?('/private/secret.txt')
      assert @host.can_crawl?('/private/allowed/file.txt')
    end

    should 'handle wildcard patterns in can_crawl?' do
      robots_content = <<~ROBOTS
        User-agent: *
        Disallow: /*.pdf
        Disallow: /temp*
      ROBOTS
      
      @host.update(robots_txt_content: robots_content)
      
      assert_not @host.can_crawl?('/document.pdf')
      assert_not @host.can_crawl?('/temp/file.txt')
      assert_not @host.can_crawl?('/temporary')
      assert @host.can_crawl?('/document.txt')
    end

    should 'handle user-agent specific rules in can_crawl?' do
      robots_content = <<~ROBOTS
        User-agent: badbot
        Disallow: /

        User-agent: *
        Disallow: /admin/
      ROBOTS
      
      @host.update(robots_txt_content: robots_content)
      
      assert_not @host.can_crawl?('/anything', 'badbot')
      assert_not @host.can_crawl?('/admin/panel', '*')
      assert @host.can_crawl?('/public/file', '*')
    end

    should 'return true for can_crawl_api? when no robots.txt content' do
      assert @host.can_crawl_api?
    end

    should 'return true for can_crawl_api? when api is allowed' do
      robots_content = <<~ROBOTS
        User-agent: *
        Disallow: /admin/
        Allow: /api/
      ROBOTS
      
      @host.update(robots_txt_content: robots_content)
      assert @host.can_crawl_api?
    end

    should 'return false for can_crawl_api? when root is blocked' do
      robots_content = <<~ROBOTS
        User-agent: *
        Disallow: /
      ROBOTS
      
      @host.update(robots_txt_content: robots_content, robots_txt_updated_at: 1.hour.ago)
      assert_not @host.can_crawl_api?
    end

    should 'return false for can_crawl_api? when api is specifically blocked' do
      robots_content = <<~ROBOTS
        User-agent: *
        Disallow: /api/
      ROBOTS
      
      @host.update(robots_txt_content: robots_content)
      assert_not @host.can_crawl_api?
    end

    should 'return http_client instance for allowed path' do
      stub_request(:get, "https://example.com/").to_return(status: 200, body: "")
      stub_request(:get, "https://example.com/robots.txt").to_return(status: 200, body: "")
      client = @host.http_client('/public')
      assert_instance_of Faraday::Connection, client
    end

    should 'return nil for http_client when path is blocked' do
      robots_content = <<~ROBOTS
        User-agent: *
        Disallow: /private/
      ROBOTS
      
      @host.update(robots_txt_content: robots_content, robots_txt_updated_at: 1.hour.ago, status: 'online', status_checked_at: 1.hour.ago)
      stub_request(:get, "https://example.com/").to_return(status: 200, body: "")
      
      assert_nil @host.http_client('/private/secret')
    end

    should 'return nil for api_client when api access is blocked' do
      robots_content = <<~ROBOTS
        User-agent: *
        Disallow: /api/
      ROBOTS
      
      @host.update(robots_txt_content: robots_content, robots_txt_updated_at: 1.hour.ago, status: 'online', status_checked_at: 1.hour.ago)
      stub_request(:get, "https://example.com/").to_return(status: 200, body: "")
      
      assert_nil @host.api_client
    end

    should 'return api_client when api access is allowed' do
      stub_request(:get, "https://example.com/").to_return(status: 200, body: "")
      stub_request(:get, "https://example.com/robots.txt").to_return(status: 200, body: "")
      client = @host.api_client
      assert_instance_of Faraday::Connection, client
    end

    should 'handle 404 robots.txt as allowed crawling' do
      stub_request(:get, "https://example.com/robots.txt").to_return(status: 404)
      
      @host.fetch_robots_txt
      assert_equal 'not_found', @host.robots_txt_status
      assert_nil @host.robots_txt_content
      assert @host.can_crawl_api?
    end

    should 'handle other HTTP errors as blocked crawling' do
      stub_request(:get, "https://example.com/robots.txt").to_return(status: 500)
      
      @host.fetch_robots_txt
      assert_equal 'error_500', @host.robots_txt_status
      assert_nil @host.robots_txt_content
    end
  end

  context 'host status functionality' do
    setup do
      @host = create(:host, url: 'https://example.com')
    end

    should 'return online status when host responds successfully' do
      stub_request(:get, "https://example.com").to_return(status: 200, body: "OK")
      
      status = @host.check_status
      assert_equal 'online', status
      assert_equal 'online', @host.status
      assert @host.online?
      assert_not @host.offline?
      assert_not_nil @host.response_time
      assert_nil @host.last_error
    end

    should 'return online status when redirects lead to successful response' do
      # Test 301 redirect followed by successful response
      stub_request(:get, "https://example.com").to_return(status: 301, headers: {'Location' => 'https://www.example.com'})
      stub_request(:get, "https://www.example.com").to_return(status: 200, body: "OK")
      
      status = @host.check_status
      assert_equal 'online', status
      assert_equal 'online', @host.status
      assert @host.online?
      assert_not @host.offline?
      assert_not_nil @host.response_time
      assert_nil @host.last_error
    end

    should 'return http_error status when redirect leads to error' do
      # Test 302 redirect followed by 404 error
      stub_request(:get, "https://example.com").to_return(status: 302, headers: {'Location' => 'https://www.example.com/missing'})
      stub_request(:get, "https://www.example.com/missing").to_return(status: 404, body: "Not Found")
      
      status = @host.check_status
      assert_equal 'http_error', status
      assert_not @host.online?
      assert @host.offline?
      assert_includes @host.last_error, "HTTP 404"
    end

    should 'return http_error status for non-success non-redirect responses' do
      stub_request(:get, "https://example.com").to_return(status: 404, body: "Not Found")
      
      status = @host.check_status
      assert_equal 'http_error', status
      assert_equal 'http_error', @host.status
      assert_not @host.online?
      assert @host.offline?
      assert_includes @host.last_error, "HTTP 404"
    end

    should 'handle connection failed errors' do
      stub_request(:get, "https://example.com").to_raise(Faraday::ConnectionFailed.new("Connection refused"))
      
      status = @host.check_status
      assert_equal 'connection_failed', status
      assert_equal 'connection_failed', @host.status
      assert_not @host.online?
      assert @host.offline?
      assert_includes @host.last_error, "Connection refused"
      assert_nil @host.response_time
    end

    should 'handle timeout errors' do
      stub_request(:get, "https://example.com").to_raise(Faraday::TimeoutError.new("Timeout"))
      
      status = @host.check_status
      assert_equal 'timeout', status
      assert_equal 'timeout', @host.status
      assert_not @host.online?
      assert @host.offline?
      assert_includes @host.last_error, "Timeout"
    end

    should 'handle SSL errors' do
      stub_request(:get, "https://example.com").to_raise(Faraday::SSLError.new("SSL Error"))
      
      status = @host.check_status
      assert_equal 'ssl_error', status
      assert_equal 'ssl_error', @host.status
      assert_not @host.online?
      assert @host.offline?
      assert_includes @host.last_error, "SSL Error"
    end

    should 'return true for status_stale? when never checked' do
      assert @host.status_stale?
    end

    should 'return false for status_stale? when recently checked' do
      @host.update(status_checked_at: 30.minutes.ago)
      assert_not @host.status_stale?
    end

    should 'return true for status_stale? when old' do
      @host.update(status_checked_at: 2.hours.ago)
      assert @host.status_stale?
    end

    should 'return correct status colors' do
      @host.update(status: 'online')
      assert_equal 'success', @host.status_color

      @host.update(status: 'timeout')
      assert_equal 'warning', @host.status_color

      @host.update(status: 'http_error')
      assert_equal 'danger', @host.status_color

      @host.update(status: 'unknown')
      assert_equal 'secondary', @host.status_color
    end

    should 'return correct status descriptions' do
      @host.update(status: 'online', response_time: 150)
      assert_equal 'Online (150ms)', @host.status_description

      @host.update(status: 'timeout')
      assert_equal 'Request timeout', @host.status_description

      @host.update(status: 'connection_failed')
      assert_equal 'Connection failed', @host.status_description
    end

    should 'skip HTTP requests for offline hosts' do
      @host.update(status: 'timeout', status_checked_at: 30.minutes.ago)
      
      client = @host.http_client('/api')
      assert_nil client
    end

    should 'skip API requests for offline hosts' do
      @host.update(status: 'connection_failed', status_checked_at: 30.minutes.ago)
      
      client = @host.api_client
      assert_nil client
    end
  end

  context 'sync_repository method' do
    setup do
      @host = create(:host, url: 'https://example.com', kind: 'github')
    end

    should 'skip repository creation when API returns garbage data' do
      # Stub the API call to return garbage data with nil essential fields
      garbage_response = {
        "id" => nil,
        "name" => nil,
        "full_name" => nil,
        "description" => nil, 
        "created_at" => nil,
        "updated_at" => Time.current.iso8601,
        "stargazers_count" => 0,
        "owner" => nil,
        "private" => false
      }
      
      stub_request(:get, "https://api.github.com/repos/test/repo")
        .to_return(status: 200, body: garbage_response.to_json, headers: {'Content-Type' => 'application/json'})
      
      result = @host.sync_repository('test/repo')
      assert_nil result
      assert_equal 0, @host.repositories.count
    end

    should 'skip repository creation when created_at is missing' do
      # Test that repositories with missing created_at are skipped
      response_without_created_at = {
        "id" => 123456,
        "name" => "repo",
        "full_name" => "test/repo", 
        "description" => "A test repository",
        "created_at" => nil,
        "updated_at" => Time.current.iso8601,
        "stargazers_count" => 10,
        "owner" => {"login" => "test"},
        "private" => false
      }
      
      stub_request(:get, "https://api.github.com/repos/test/repo")
        .to_return(status: 200, body: response_without_created_at.to_json, headers: {'Content-Type' => 'application/json'})
      
      result = @host.sync_repository('test/repo')
      assert_nil result
      assert_equal 0, @host.repositories.count
    end

    should 'process repository when API returns valid data with some fields present' do
      # Test that repositories with some valid essential fields get processed
      partial_valid_response = {
        "id" => 123456,
        "name" => "repo", 
        "full_name" => "test/repo",
        "description" => nil, # This is blank but not all essential fields
        "created_at" => Time.current.iso8601,
        "updated_at" => Time.current.iso8601,
        "stargazers_count" => 10,
        "owner" => {"login" => "test"},
        "private" => false
      }
      
      stub_request(:get, "https://api.github.com/repos/test/repo")
        .to_return(status: 200, body: partial_valid_response.to_json, headers: {'Content-Type' => 'application/json'})
      
      # Stub the GraphQL owner sync request to prevent additional API calls
      stub_request(:post, "https://api.github.com/graphql")
        .to_return(status: 200, body: '{"data": {"repositoryOwner": null}}', headers: {'Content-Type' => 'application/json'})
      
      result = @host.sync_repository('test/repo')
      assert_not_nil result
      assert_equal 1, @host.repositories.count
      assert_equal 'test/repo', result.full_name
    end
  end

  context 'sync_repos_with_tags' do
    setup do
      @host = create(:github_host)
    end

    should 'handle nil response from load_repos_with_tags' do
      github_instance = @host.host_instance
      github_instance.stubs(:load_repos_with_tags).returns(nil)

      assert_nothing_raised do
        github_instance.sync_repos_with_tags
      end
    end

    should 'handle empty response from load_repos_with_tags' do
      github_instance = @host.host_instance
      github_instance.stubs(:load_repos_with_tags).returns([])

      assert_nothing_raised do
        github_instance.sync_repos_with_tags
      end
    end

    should 'sync repositories from tag events' do
      github_instance = @host.host_instance
      github_instance.stubs(:load_repos_with_tags).returns([
        {"repository" => "owner/repo1"},
        {"repository" => "owner/repo2"},
        {"repository" => "owner/repo1"}
      ])

      Host.stubs(:find_by_name).with("GitHub").returns(@host)
      @host.expects(:find_repository).with("owner/repo1").returns(nil)
      @host.expects(:find_repository).with("owner/repo2").returns(nil)
      @host.expects(:sync_repository_async).with("owner/repo1").once
      @host.expects(:sync_repository_async).with("owner/repo2").once

      github_instance.sync_repos_with_tags
    end
  end

  context 'GitLab host specific functionality' do
    setup do
      @gitlab_host = create(:gitlab_host)
    end

    should 'handle nil API response in load_owner_repos_names for user' do
      user_owner = create(:gitlab_owner, host: @gitlab_host, kind: 'user')
      
      gitlab_instance = @gitlab_host.host_instance
      gitlab_instance.expects(:api_client).returns(mock('api_client').tap { |m| m.expects(:user_projects).returns(nil) })
      
      result = gitlab_instance.load_owner_repos_names(user_owner)
      assert_equal [], result
    end

    should 'handle nil API response in load_owner_repos_names for organization' do
      org_owner = create(:gitlab_owner, host: @gitlab_host, kind: 'organization')
      
      gitlab_instance = @gitlab_host.host_instance
      gitlab_instance.expects(:api_client).returns(mock('api_client').tap { |m| m.expects(:group_projects).returns(nil) })
      
      result = gitlab_instance.load_owner_repos_names(org_owner)
      assert_equal [], result
    end

    should 'return empty array when API client returns empty response' do
      user_owner = create(:gitlab_owner, host: @gitlab_host, kind: 'user')
      
      gitlab_instance = @gitlab_host.host_instance
      gitlab_instance.expects(:api_client).returns(mock('api_client').tap { |m| m.expects(:user_projects).returns([]) })
      
      result = gitlab_instance.load_owner_repos_names(user_owner)
      assert_equal [], result
    end
  end

  context 'sync_owner_repositories methods' do
    setup do
      @host = FactoryBot.create(:github_host)
      @visible_owner = FactoryBot.create(:owner, host: @host, hidden: false)
      @hidden_owner = FactoryBot.create(:hidden_owner, host: @host)
    end

    should 'not sync repositories for hidden owners in sync_owner_repositories' do
      @host.host_instance.expects(:load_owner_repos_names).never
      @host.sync_owner_repositories(@hidden_owner)
    end

    should 'sync repositories for visible owners in sync_owner_repositories' do
      @host.stubs(:host_instance).returns(mock('host_instance').tap do |m|
        m.expects(:load_owner_repos_names).with(@visible_owner).returns(['owner/repo1', 'owner/repo2'])
      end)
      @host.expects(:sync_repository).with('owner/repo1').once
      @host.expects(:sync_repository).with('owner/repo2').once
      @host.sync_owner_repositories(@visible_owner)
    end

    should 'not sync repositories for hidden owners in sync_owner_repositories_async' do
      @host.host_instance.expects(:load_owner_repos_names).never
      @host.sync_owner_repositories_async(@hidden_owner)
    end

    should 'sync repositories for visible owners in sync_owner_repositories_async' do
      @host.stubs(:host_instance).returns(mock('host_instance').tap do |m|
        m.expects(:load_owner_repos_names).with(@visible_owner).returns(['owner/repo1', 'owner/repo2'])
      end)
      @host.expects(:sync_repository_async).with('owner/repo1').once
      @host.expects(:sync_repository_async).with('owner/repo2').once
      @host.sync_owner_repositories_async(@visible_owner)
    end
  end

  context 'sync_repository method' do
    setup do
      @host = FactoryBot.create(:github_host)
      @visible_owner = FactoryBot.create(:owner, host: @host, login: 'visible', hidden: false)
      @hidden_owner = FactoryBot.create(:hidden_owner, host: @host, login: 'hidden')
    end

    should 'not sync repository when owner is hidden' do
      result = @host.sync_repository('hidden/repo')
      assert_nil result
    end

    should 'sync repository when owner is visible' do
      @host.stubs(:host_instance).returns(mock('host_instance').tap do |m|
        m.expects(:fetch_repository).with('visible/repo').returns({
          uuid: '12345',
          id: '12345',
          full_name: 'visible/repo',
          description: 'Test repo',
          created_at: 1.week.ago,
          updated_at: 1.day.ago,
          owner: 'visible'
        })
      end)

      repository = @host.sync_repository('visible/repo')
      assert_equal 'visible/repo', repository.full_name
    end

    should 'sync existing repository when owner is visible' do
      existing_repo = FactoryBot.create(:repository, host: @host, full_name: 'visible/repo', owner: 'visible')

      @host.stubs(:host_instance).returns(mock('host_instance').tap do |m|
        m.expects(:update_from_host).with(existing_repo).once
      end)

      @host.sync_repository('visible/repo')
    end
  end

  context 'sync_owner method' do
    setup do
      @host = FactoryBot.create(:github_host)
    end

    should 'not sync repositories for hidden owners' do
      hidden_owner = FactoryBot.create(:hidden_owner, host: @host, login: 'hiddenuser', last_synced_at: 2.weeks.ago)

      @host.stubs(:host_instance).returns(mock('host_instance').tap do |m|
        m.expects(:fetch_owner).with('hiddenuser').returns({
          uuid: '12345',
          login: 'hiddenuser',
          name: 'Hidden User',
          hidden: true
        })
      end)

      result = @host.sync_owner('hiddenuser')
      assert_equal 'hiddenuser', result.login
      assert_equal true, result.hidden
    end

    should 'sync repositories for visible owners' do
      visible_owner = FactoryBot.create(:owner, host: @host, login: 'visibleuser', last_synced_at: 2.weeks.ago, hidden: false)

      @host.stubs(:host_instance).returns(mock('host_instance').tap do |m|
        m.expects(:fetch_owner).with('visibleuser').returns({
          uuid: '67890',
          login: 'visibleuser',
          name: 'Visible User',
          hidden: false
        })
        m.expects(:load_owner_repos_names).with(visible_owner).returns(['visibleuser/repo1'])
      end)

      @host.expects(:sync_repository_async).with('visibleuser/repo1').once

      result = @host.sync_owner('visibleuser')
      assert_equal 'visibleuser', result.login
      assert_equal false, result.hidden
    end
  end
end
