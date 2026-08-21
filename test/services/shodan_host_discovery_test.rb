require "test_helper"

class ShodanHostDiscoveryTest < ActiveSupport::TestCase
  SEARCH_URL = "https://api.shodan.io/shodan/host/search"

  setup do
    @query = 'http.html:"Powered by Gitea"'
  end

  def stub_search(matches, query: @query, page: 1, status: 200, body: nil)
    body ||= { 'matches' => matches, 'total' => matches.length }.to_json

    stub_request(:get, SEARCH_URL)
      .with(query: { 'key' => 'shodan-key', 'query' => query, 'page' => page.to_s })
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_gitea(domain, version: '1.22.0', forgejo: false, repositories: 1)
    stub_request(:get, "https://#{domain}/robots.txt").to_return(status: 404, body: '')
    stub_request(:get, "https://#{domain}/api/v1/version")
      .to_return(status: 200, body: { version: version }.to_json)
    stub_request(:get, "https://#{domain}/api/v1/repos/search?limit=1")
      .to_return(status: 200, body: { ok: true, data: Array.new(repositories) { |i| { id: i } } }.to_json)

    if forgejo
      stub_request(:get, "https://#{domain}/api/forgejo/v1/version")
        .to_return(status: 200, body: { version: '11.0.0' }.to_json)
    else
      stub_request(:get, "https://#{domain}/api/forgejo/v1/version").to_return(status: 404, body: '')
    end
  end

  def stub_gitlab(domain, projects: [{ id: 1 }])
    stub_request(:get, "https://#{domain}/robots.txt").to_return(status: 404, body: '')
    stub_request(:get, "https://#{domain}/api/v1/version").to_return(status: 404, body: '')
    stub_request(:get, "https://#{domain}/api/v4/projects?per_page=1&simple=true")
      .to_return(status: 200, body: projects.to_json)
  end

  def discovery(**options)
    ShodanHostDiscovery.new(**{ api_key: 'shodan-key', queries: [@query] }.merge(options))
  end

  test "raises when no api key is configured" do
    assert_raises(ShodanHostDiscovery::MissingApiKey) do
      discovery(api_key: nil).discover
    end
  end

  test "finds a gitea instance" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_gitea('git.example.com')

    result = discovery.discover

    assert_equal 1, result[:found]
    assert_equal 1, result[:probed]
    candidate = result[:candidates].sole
    assert_equal 'git.example.com', candidate.domain
    assert_equal 'https://git.example.com', candidate.url
    assert_equal 'gitea', candidate.kind
    assert_equal '1.22.0', candidate.version
    assert_empty result[:created]
  end

  test "identifies forgejo by its own version api" do
    stub_search([{ 'hostnames' => ['forge.example.com'] }])
    stub_gitea('forge.example.com', forgejo: true)

    assert_equal 'forgejo', discovery.discover[:candidates].sole.kind
  end

  test "finds a gitlab instance by listing projects anonymously" do
    stub_search([{ 'hostnames' => ['gitlab.example.com'] }])
    stub_gitlab('gitlab.example.com')

    candidate = discovery.discover[:candidates].sole
    assert_equal 'gitlab', candidate.kind
    assert_nil candidate.version
  end

  test "skips instances with no public repositories" do
    stub_search([{ 'hostnames' => ['empty.example.com'], 'http' => { 'host' => 'gitlab.example.com' } }])
    stub_gitea('empty.example.com', repositories: 0)
    stub_request(:get, "https://empty.example.com/api/v4/projects?per_page=1&simple=true")
      .to_return(status: 404, body: '')
    stub_gitlab('gitlab.example.com', projects: [])

    result = discovery.discover

    assert_equal 2, result[:probed]
    assert_empty result[:candidates]
  end

  test "skips instances that disallow crawling in robots.txt" do
    stub_search([{ 'hostnames' => ['private.example.com'] }])
    stub_request(:get, "https://private.example.com/robots.txt")
      .to_return(status: 200, body: "User-agent: *\nDisallow: /\n")

    assert_empty discovery.discover[:candidates]
    assert_not_requested :get, "https://private.example.com/api/v1/version"
  end

  test "skips instances that disallow the api in robots.txt" do
    stub_search([{ 'hostnames' => ['api-blocked.example.com'] }])
    stub_request(:get, "https://api-blocked.example.com/robots.txt")
      .to_return(status: 200, body: "User-agent: *\nDisallow: /api\n")

    assert_empty discovery.discover[:candidates]
    assert_not_requested :get, "https://api-blocked.example.com/api/v1/version"
  end

  test "skips domains that resolve inside our own network" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    service = discovery
    service.stubs(:resolved_addresses).with('git.example.com').returns([IPAddr.new('127.0.0.1')])

    result = service.discover

    assert_equal 1, result[:probed]
    assert_empty result[:candidates]
    assert_not_requested :get, "https://git.example.com/robots.txt"
  end

  test "does not follow redirects off the candidate" do
    metadata = 'http://169.254.169.254/latest/meta-data/'
    stub_search([{ 'hostnames' => ['redirect.example.com'] }])
    stub_request(:get, "https://redirect.example.com/robots.txt").to_return(status: 404, body: '')
    stub_request(:get, "https://redirect.example.com/api/v1/version")
      .to_return(status: 302, headers: { 'Location' => metadata })
    stub_request(:get, "https://redirect.example.com/api/v4/projects?per_page=1&simple=true")
      .to_return(status: 302, headers: { 'Location' => metadata })

    assert_empty discovery.discover[:candidates]
    assert_not_requested :get, metadata
  end

  test "skips hosts that are already known" do
    create(:host, name: 'Known', url: 'https://git.example.com', kind: 'gitea')
    stub_search([{ 'hostnames' => ['git.example.com'] }])

    result = discovery.discover

    assert_equal 1, result[:found]
    assert_equal 0, result[:probed]
    assert_empty result[:candidates]
  end

  test "ignores ip addresses and unroutable hostnames" do
    stub_search([{ 'hostnames' => ['192.168.0.1', 'git.local', 'git.localhost', 'localhost', 'gitea'], 'http' => { 'host' => '10.0.0.1' } }])

    assert_equal 0, discovery.discover[:found]
  end

  test "deduplicates domains across matches and queries" do
    other_query = 'http.title:"GitLab"'
    stub_search([{ 'hostnames' => ['git.example.com'], 'http' => { 'host' => 'git.example.com' } }])
    stub_search([{ 'hostnames' => ['git.example.com'] }], query: other_query)
    stub_gitea('git.example.com')

    result = discovery(queries: [@query, other_query]).discover

    assert_equal 1, result[:found]
    assert_equal 1, result[:candidates].length
  end

  test "stops paging when a page is not full" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_gitea('git.example.com')

    discovery(pages: 3).discover

    assert_not_requested :get, SEARCH_URL, query: hash_including({ 'page' => '2' })
  end

  test "creates hosts when asked to" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_gitea('git.example.com')

    result = discovery(create: true).discover

    host = result[:created].sole
    assert_equal 'git.example.com', host.name
    assert_equal 'https://git.example.com', host.url
    assert_equal 'gitea', host.kind
    assert_equal '1.22.0', host.version
    assert_equal 1, Host.where(url: 'https://git.example.com').count
  end

  test "reports rather than raises when a host cannot be saved" do
    create(:host, name: 'git.example.com', url: 'https://other.example.com', kind: 'gitea')
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_gitea('git.example.com')
    output = StringIO.new

    result = discovery(create: true, output: output).discover

    assert_equal 1, result[:candidates].length
    assert_empty result[:created]
    assert_includes output.string, 'skipping git.example.com'
  end

  test "raises without leaking the api key when shodan rejects the request" do
    stub_search([], status: 401, body: { error: 'Invalid API key' }.to_json)

    error = assert_raises(ShodanHostDiscovery::ApiError) { discovery.discover }

    assert_includes error.message, 'HTTP 401'
    assert_includes error.message, 'Invalid API key'
    assert_not_includes error.message, 'shodan-key'
  end

  test "raises when shodan returns an unreadable body" do
    stub_search([], body: '<html>nope</html>')

    assert_raises(ShodanHostDiscovery::ApiError) { discovery.discover }
  end

  test "raises when shodan cannot be reached" do
    stub_request(:get, SEARCH_URL).with(query: hash_including({})).to_timeout

    assert_raises(ShodanHostDiscovery::ApiError) { discovery.discover }
  end

  test "skips a candidate that stops responding mid-probe" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_request(:get, "https://git.example.com/robots.txt").to_return(status: 404, body: '')
    stub_request(:get, "https://git.example.com/api/v1/version").to_timeout
    stub_request(:get, "https://git.example.com/api/v4/projects?per_page=1&simple=true").to_timeout

    assert_empty discovery.discover[:candidates]
  end

  test "limits how many unknown domains are probed" do
    stub_search([{ 'hostnames' => ['a.example.com', 'b.example.com'] }])
    stub_gitea('a.example.com')

    result = discovery(limit: 1).discover

    assert_equal 2, result[:found]
    assert_equal 1, result[:probed]
    assert_equal 1, result[:candidates].length
    assert_not_requested :get, "https://b.example.com/robots.txt"
  end
end
