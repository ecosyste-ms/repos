require "test_helper"

class HostTest < ActiveSupport::TestCase
  context 'associations' do
    should have_many(:repositories)
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
      
      @host.update(robots_txt_content: robots_content)
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

    should 'return http_error status for non-success responses' do
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
end
