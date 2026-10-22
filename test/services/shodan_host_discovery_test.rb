require "test_helper"

class ShodanHostDiscoveryTest < ActiveSupport::TestCase
  SEARCH_URL = "https://api.shodan.io/shodan/host/search"

  setup do
    @query = 'http.html:"Powered by Gitea"'
    Resolv.stubs(:getaddresses).returns(['203.0.113.10'])
  end

  teardown do
    REDIS.scan_each(match: "#{ShodanHostDiscovery::REJECTION_KEY_PREFIX}*.example.com") { |key| REDIS.del(key) }
  end

  def rejection(domain)
    key = "#{ShodanHostDiscovery::REJECTION_KEY_PREFIX}#{domain}"
    [REDIS.get(key), REDIS.ttl(key)]
  end

  def stub_search(matches, query: @query, page: 1, status: 200, body: nil)
    body ||= { 'matches' => matches, 'total' => matches.length }.to_json

    stub_request(:get, SEARCH_URL)
      .with(query: { 'key' => 'shodan-key', 'query' => query, 'page' => page.to_s })
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_gitea(domain, version: '1.22.0', forgejo: false, repositories: 1, root_url: "https://#{domain}")
    stub_request(:get, "https://#{domain}/robots.txt").to_return(status: 404, body: '')
    stub_request(:get, "https://#{domain}/api/v1/version")
      .to_return(status: 200, body: { version: version }.to_json)
    stub_request(:get, "https://#{domain}/api/v1/repos/search?limit=1")
      .to_return(status: 200, body: { ok: true, data: Array.new(repositories) { |i| { id: i, html_url: "#{root_url}/owner/repo#{i}" } } }.to_json)

    if forgejo
      stub_request(:get, "https://#{domain}/api/forgejo/v1/version")
        .to_return(status: 200, body: { version: '11.0.0' }.to_json)
    else
      stub_request(:get, "https://#{domain}/api/forgejo/v1/version").to_return(status: 404, body: '')
    end
  end

  def stub_gitlab(domain, projects: [{ id: 1, web_url: "https://#{domain}/group/project" }])
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

  test "ignores robots.txt rules that only cover the api" do
    stub_search([{ 'hostnames' => ['api-blocked.example.com'] }])
    stub_gitea('api-blocked.example.com', forgejo: true)
    stub_request(:get, "https://api-blocked.example.com/robots.txt")
      .to_return(status: 200, body: "User-agent: *\nDisallow: /api\n")

    assert_equal 'forgejo', discovery.discover[:candidates].sole.kind
  end

  test "skips domains that resolve inside our own network" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    Resolv.stubs(:getaddresses).with('git.example.com').returns(['127.0.0.1'])

    result = discovery.discover

    assert_equal 1, result[:probed]
    assert_empty result[:candidates]
    assert_not_requested :get, "https://git.example.com/robots.txt"
  end

  test "skips domains with any address inside our own network" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    Resolv.stubs(:getaddresses).with('git.example.com').returns(['203.0.113.10', '10.0.0.1'])

    assert_empty discovery.discover[:candidates]
    assert_not_requested :get, "https://git.example.com/robots.txt"
  end

  test "skips domains that do not resolve" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    Resolv.stubs(:getaddresses).with('git.example.com').returns([])

    assert_empty discovery.discover[:candidates]
    assert_not_requested :get, "https://git.example.com/robots.txt"
  end

  test "connects to the vetted address even when a proxy is configured" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    dialed = []
    TCPSocket.stubs(:open).with { |address, *| dialed << address }.raises(Errno::ECONNREFUSED)
    WebMock.disable_net_connect!(allow: 'git.example.com')
    previous_proxy = ENV['https_proxy']
    ENV['https_proxy'] = 'http://proxy.example.com:3128'

    assert_empty discovery.discover[:candidates]
    assert_equal ['203.0.113.10'], dialed.uniq
  ensure
    ENV['https_proxy'] = previous_proxy
    WebMock.disable_net_connect!
  end

  test "probes gitlab behind its stock robots.txt" do
    stub_search([{ 'hostnames' => ['gitlab.example.com'] }])
    stub_gitlab('gitlab.example.com')
    stub_request(:get, "https://gitlab.example.com/robots.txt")
      .to_return(status: 200, body: "User-Agent: *\nDisallow: /api/v*\nDisallow: /search\n")

    assert_equal 'gitlab', discovery.discover[:candidates].sole.kind
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

  test "reports an alias under the name its repositories link to" do
    stub_search([{ 'hostnames' => ['cloud.example.com'] }])
    stub_gitea('cloud.example.com', root_url: 'https://dev.example.com')
    stub_gitea('dev.example.com')

    result = discovery.discover

    assert_equal ['dev.example.com'], result[:candidates].map(&:domain)
  end

  test "reports an instance once when shodan returns it under two names" do
    stub_search([{ 'hostnames' => ['cloud.example.com', 'dev.example.com'] }])
    stub_gitea('cloud.example.com', root_url: 'https://dev.example.com')
    stub_gitea('dev.example.com')

    assert_equal ['dev.example.com'], discovery.discover[:candidates].map(&:domain)
  end

  test "skips an alias of a known host" do
    create(:host, name: 'Known', url: 'https://dev.example.com', kind: 'gitea')
    stub_search([{ 'hostnames' => ['cloud.example.com'] }])
    stub_gitea('cloud.example.com', root_url: 'https://dev.example.com')

    assert_empty discovery.discover[:candidates]
    assert_not_requested :get, "https://dev.example.com/robots.txt"
  end

  test "reports a gitlab alias under the name its projects link to" do
    stub_search([{ 'hostnames' => ['code.example.com'] }])
    stub_gitlab('code.example.com', projects: [{ id: 1, web_url: 'https://gitlab.example.com/group/project' }])
    stub_gitlab('gitlab.example.com')

    assert_equal ['gitlab.example.com'], discovery.discover[:candidates].map(&:domain)
  end

  test "keeps the probed name when repositories link to an unroutable one" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_gitea('git.example.com', root_url: 'http://localhost:3000')

    assert_equal ['git.example.com'], discovery.discover[:candidates].map(&:domain)
  end

  test "follows an alias only one step" do
    stub_search([{ 'hostnames' => ['a.example.com'] }])
    stub_gitea('a.example.com', root_url: 'https://b.example.com')
    stub_gitea('b.example.com', root_url: 'https://c.example.com')

    assert_empty discovery.discover[:candidates]
    assert_not_requested :get, "https://c.example.com/robots.txt"
  end

  test "falls back to plain http when nothing answers over https" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_request(:get, %r{\Ahttps://git\.example\.com/}).to_raise(Errno::ECONNREFUSED)
    stub_request(:get, "http://git.example.com/robots.txt").to_return(status: 404, body: '')
    stub_request(:get, "http://git.example.com/api/v1/version").to_return(status: 200, body: { version: '1.22.0' }.to_json)
    stub_request(:get, "http://git.example.com/api/forgejo/v1/version").to_return(status: 404, body: '')
    stub_request(:get, "http://git.example.com/api/v1/repos/search?limit=1")
      .to_return(status: 200, body: { ok: true, data: [{ id: 1, html_url: 'http://git.example.com/owner/repo' }] }.to_json)

    candidate = discovery.discover[:candidates].sole

    assert_equal 'http://git.example.com', candidate.url
  end

  test "does not fall back to plain http when https times out" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_request(:get, "https://git.example.com/robots.txt").to_timeout

    result = discovery.discover

    assert_equal({ unreachable: 1 }, result[:rejections])
    assert_not_requested :get, "http://git.example.com/robots.txt"
  end

  test "does not try plain http when https answers" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_gitea('git.example.com')

    assert_equal 'https://git.example.com', discovery.discover[:candidates].sole.url
    assert_not_requested :get, "http://git.example.com/robots.txt"
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

  test "ignores hostnames built from an ip address" do
    stub_search([{ 'hostnames' => ['222.154.123.34.bc.googleusercontent.com', 'ec2-3-111-58-77.ap-south-1.compute.amazonaws.com',
                                   'static.244.249.108.65.clients.your-server.de'] }])

    assert_equal 0, discovery.discover[:found]
  end

  test "keeps hostnames that only contain some numbers" do
    stub_search([{ 'hostnames' => ['git.web3.example.com', 'git-2024.example.com'] }])
    stub_gitea('git.web3.example.com')
    stub_gitea('git-2024.example.com')

    assert_equal 2, discovery.discover[:found]
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

  test "remembers why a domain was rejected until it is worth rechecking" do
    stub_search([{ 'hostnames' => ['empty.example.com', 'down.example.com'] }])
    stub_gitea('empty.example.com', repositories: 0)
    stub_request(:get, "https://empty.example.com/api/v4/projects?per_page=1&simple=true").to_return(status: 404, body: '')
    stub_request(:get, "https://down.example.com/robots.txt").to_timeout

    result = discovery.discover

    assert_equal({ no_public_repositories: 1, unreachable: 1 }, result[:rejections])
    reason, ttl = rejection('empty.example.com')
    assert_equal 'no_public_repositories', reason
    assert_in_delta ShodanHostDiscovery::REJECTION_TTL.to_i, ttl, 5
    reason, ttl = rejection('down.example.com')
    assert_equal 'unreachable', reason
    assert_in_delta ShodanHostDiscovery::TRANSIENT_REJECTION_TTL.to_i, ttl, 5
  end

  test "labels a domain with no forge api as not a forge" do
    stub_search([{ 'hostnames' => ['www.example.com'] }])
    stub_request(:get, "https://www.example.com/robots.txt").to_return(status: 404, body: '')
    stub_request(:get, "https://www.example.com/api/v1/version").to_return(status: 404, body: '')
    stub_request(:get, "https://www.example.com/api/v4/projects?per_page=1&simple=true").to_return(status: 404, body: '')

    discovery.discover

    assert_equal 'not_a_forge', rejection('www.example.com').first
  end

  test "does not remember candidates" do
    stub_search([{ 'hostnames' => ['git.example.com'] }])
    stub_gitea('git.example.com')

    discovery.discover

    assert_nil rejection('git.example.com').first
  end

  test "spends the probe limit on domains not rejected before" do
    REDIS.set("#{ShodanHostDiscovery::REJECTION_KEY_PREFIX}a.example.com", 'not_a_forge')
    stub_search([{ 'hostnames' => ['a.example.com', 'b.example.com'] }])
    stub_gitea('b.example.com')

    result = discovery(limit: 1).discover

    assert_equal 1, result[:previously_rejected]
    assert_equal ['b.example.com'], result[:candidates].map(&:domain)
    assert_not_requested :get, "https://a.example.com/robots.txt"
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
