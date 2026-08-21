require 'ipaddr'
require 'resolv'

# Finds public gitea/forgejo/gitlab instances with shodan.io so they can be indexed.
#
# Shodan only supplies candidate domains, each candidate is then probed directly
# to work out what it actually runs and whether its repositories are readable
# without an account. Instances that are already known, that block us in
# robots.txt or that expose no public repositories are dropped.
class ShodanHostDiscovery
  class MissingApiKey < StandardError; end
  class ApiError < StandardError; end

  SHODAN_API_URL = 'https://api.shodan.io'
  RESULTS_PER_PAGE = 100

  QUERIES = [
    'http.html:"Powered by Gitea"',
    'http.html:"Powered by Forgejo"',
    'http.title:"GitLab"'
  ].freeze

  DEFAULT_PAGES = 1
  DEFAULT_LIMIT = 50
  TIMEOUT = 10

  DOMAIN = /\A[a-z0-9]([a-z0-9\-.]*[a-z0-9])?\.[a-z]{2,}\z/
  RESERVED_DOMAIN = /\.(local|localhost|localdomain|internal|intranet|lan|home|test|invalid|example|arpa)\z/

  # Ranges IPAddr has no predicate for: this network, shared address space and
  # the unspecified address.
  UNROUTABLE_RANGES = [
    IPAddr.new('0.0.0.0/8'),
    IPAddr.new('100.64.0.0/10'),
    IPAddr.new('::/128')
  ].freeze

  IGNORABLE_EXCEPTIONS = [
    Faraday::Error,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Socket::ResolutionError,
    OpenSSL::SSL::SSLError,
    URI::InvalidURIError
  ].freeze

  Candidate = Struct.new(:domain, :url, :kind, :version, keyword_init: true) do
    def to_seed_line
      %(  {name: "#{domain}", url: "#{url}", kind: "#{kind}"},)
    end
  end

  def initialize(api_key: ENV['SHODAN_API_KEY'], queries: QUERIES, pages: DEFAULT_PAGES,
                 limit: DEFAULT_LIMIT, create: false, output: $stdout)
    @api_key = api_key
    @queries = Array(queries).reject(&:blank?)
    @pages = pages.to_i.clamp(1, 20)
    @limit = limit.to_i.clamp(1, 1000)
    @create = create
    @output = output
  end

  def discover
    raise MissingApiKey, 'SHODAN_API_KEY is not set' if @api_key.blank?

    found = search_domains
    unknown = found.reject { |domain| known_domain?(domain) }.first(@limit)
    candidates = unknown.filter_map { |domain| probe(domain) }
    created = @create ? candidates.filter_map { |candidate| create_host(candidate) } : []

    { found: found.length, probed: unknown.length, candidates: candidates, created: created }
  end

  private

  def search_domains
    @queries.flat_map { |query| domains_for(query) }.uniq
  end

  def domains_for(query)
    domains = []

    (1..@pages).each do |page|
      matches = Array(search(query, page)['matches'])
      domains.concat(matches.flat_map { |match| match_domains(match) })
      break if matches.length < RESULTS_PER_PAGE
    end

    domains
  end

  def search(query, page)
    response = get("#{SHODAN_API_URL}/shodan/host/search", key: @api_key, query: query, page: page)
    raise ApiError, "shodan search for #{query} failed: no response" if response.nil?
    raise ApiError, "shodan search for #{query} failed: #{shodan_error(response)}" unless response.success?

    body = parse_json(response.body)
    raise ApiError, "shodan search for #{query} returned an unreadable response" unless body.is_a?(Hash)

    body
  end

  # Shodan reports the error itself in a json body, the api key is never echoed
  # back but the raw body is not repeated here either in case it ever is.
  def shodan_error(response)
    body = parse_json(response.body)
    message = body['error'] if body.is_a?(Hash)
    "HTTP #{response.status}#{": #{message}" if message.present?}"
  end

  def match_domains(match)
    names = Array(match['hostnames']) + [match.dig('http', 'host')]
    names.filter_map { |name| normalize_domain(name) }.uniq
  end

  def normalize_domain(name)
    domain = Host.normalize_domain(name)
    return nil if domain.blank?
    return nil unless domain.match?(DOMAIN)
    return nil if domain.match?(RESERVED_DOMAIN)

    domain
  end

  def known_domain?(domain)
    Host.find_by_domain(domain).present?
  end

  def probe(domain)
    return nil unless routable?(domain)

    url = "https://#{domain}"
    return nil unless crawlable?(url)

    gitea_candidate(domain, url) || gitlab_candidate(domain, url)
  end

  # Gitea and forgejo share the same api, only forgejo answers on its own
  # versioned namespace.
  def gitea_candidate(domain, url)
    version = version_from("#{url}/api/v1/version")
    return nil if version.blank?
    return nil unless gitea_public_repositories?(url)

    kind = version_from("#{url}/api/forgejo/v1/version").present? ? 'forgejo' : 'gitea'
    Candidate.new(domain: domain, url: url, kind: kind, version: version)
  end

  # Listing projects anonymously is the thing we need from gitlab, so it doubles
  # as the check that this is a gitlab instance worth indexing. Gitlab will not
  # report its version without a token, so it stays blank until one is
  # configured for the host.
  def gitlab_candidate(domain, url)
    projects = get_json("#{url}/api/v4/projects", per_page: 1, simple: true)
    return nil unless projects.is_a?(Array) && projects.any?

    Candidate.new(domain: domain, url: url, kind: 'gitlab', version: nil)
  end

  def gitea_public_repositories?(url)
    body = get_json("#{url}/api/v1/repos/search", limit: 1)
    body.is_a?(Hash) && Array(body['data']).any?
  end

  def version_from(url)
    body = get_json(url)
    body.is_a?(Hash) ? body['version'].presence : nil
  end

  # Everything we ask a candidate for lives under /api, so this applies the same
  # rules Host does before it calls an instance's api rather than only checking
  # the root.
  def crawlable?(url)
    response = get("#{url}/robots.txt")
    return true if response.nil? || !response.success?

    Host.new(robots_txt_content: response.body).can_crawl_api?(user_agent)
  end

  # Shodan hands us hostnames nobody has vetted, so a name pointing back inside
  # our own network is dropped before anything is fetched from it.
  def routable?(domain)
    addresses = resolved_addresses(domain)
    return true if addresses.empty?

    addresses.none? { |address| unroutable?(address) }
  end

  # A name that will not resolve is left alone, the request itself fails soon
  # enough.
  def resolved_addresses(domain)
    Resolv.getaddresses(domain).filter_map do |address|
      IPAddr.new(address).native
    rescue IPAddr::Error
      nil
    end
  end

  def unroutable?(address)
    address.loopback? || address.private? || address.link_local? ||
      UNROUTABLE_RANGES.any? { |range| range.include?(address) }
  end

  def create_host(candidate)
    Host.create!(name: candidate.domain, url: candidate.url, kind: candidate.kind, version: candidate.version)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    @output.puts "[repos] skipping #{candidate.domain}: #{e.message}"
    nil
  end

  def get_json(url, params = {})
    response = get(url, params)
    return nil if response.nil? || !response.success?

    parse_json(response.body)
  end

  def get(url, params = {})
    connection.get(url) do |req|
      req.params.update(params.stringify_keys) if params.present?
      req.options.timeout = TIMEOUT
      req.options.open_timeout = TIMEOUT
      req.headers['User-Agent'] = user_agent
    end
  rescue *IGNORABLE_EXCEPTIONS
    nil
  end

  def parse_json(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    nil
  end

  # Redirects are deliberately not followed. Every request made here is driven
  # by a hostname shodan supplied, so a Location header would be an easy way to
  # move us onto an address that was never checked.
  def connection
    @connection ||= Faraday.new do |conn|
      conn.adapter Faraday.default_adapter
    end
  end

  def user_agent
    ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
  end
end
