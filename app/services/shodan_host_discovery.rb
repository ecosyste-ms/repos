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

  # The meta keywords are in each project's default page template, so they
  # match instances that hide or reword the "Powered by" footer. Only the
  # standard ports are searched, an instance on any other port is skipped.
  QUERIES = [
    'http.html:"go,git,self-hosted,gitea" port:443,80',
    'http.html:"git,forge,forgejo" port:443,80',
    'http.title:"GitLab" port:443,80'
  ].freeze

  DEFAULT_PAGES = 1
  DEFAULT_LIMIT = 50
  TIMEOUT = 10

  GITEA_VERSION_PATH = '/api/v1/version'
  FORGEJO_VERSION_PATH = '/api/forgejo/v1/version'
  GITEA_REPOSITORIES_PATH = '/api/v1/repos/search?limit=1'
  GITLAB_PROJECTS_PATH = '/api/v4/projects?per_page=1&simple=true'

  DOMAIN = /\A[a-z0-9]([a-z0-9\-.]*[a-z0-9])?\.[a-z]{2,}\z/
  # Reverse dns names built from an address, such as
  # 222.154.123.34.bc.googleusercontent.com or ec2-3-111-58-77.compute.amazonaws.com,
  # change when the server does.
  EMBEDDED_IPV4 = /(?<!\d)\d{1,3}[.-]\d{1,3}[.-]\d{1,3}[.-]\d{1,3}(?!\d)/
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

  Candidate = Struct.new(:domain, :url, :kind, :version, :canonical_domain, keyword_init: true) do
    def to_seed_line
      %(  {name: "#{domain}", url: "#{url}", kind: "#{kind}"},)
    end
  end

  # A domain being probed: the address it was vetted at, the robots.txt it
  # published, if any, and whether it answered a forge api at all.
  Site = Struct.new(:domain, :url, :address, :robots_txt, :forge, keyword_init: true)

  REJECTION_KEY_PREFIX = 'shodan_discovery:rejected:'
  REJECTION_TTL = 180.days
  TRANSIENT_REJECTION_TTL = 14.days
  TRANSIENT_REJECTIONS = %i[unresolved unreachable].freeze

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

    @rejections = Hash.new(0)
    found = search_domains
    unknown = found.reject { |domain| known_domain?(domain) }
    unchecked = unknown.reject { |domain| recently_rejected?(domain) }
    probed = unchecked.first(@limit)
    candidates = probed.filter_map { |domain| probe(domain) }.uniq(&:domain)
    created = @create ? candidates.filter_map { |candidate| create_host(candidate) } : []

    { found: found.length, previously_rejected: unknown.length - unchecked.length, probed: probed.length,
      candidates: candidates, created: created, rejections: @rejections }
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
    response = get("#{SHODAN_API_URL}/shodan/host/search", { key: @api_key, query: query, page: page })
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
    return nil if domain.match?(EMBEDDED_IPV4)

    domain
  end

  def known_domain?(domain)
    Host.find_by_domain(domain).present?
  end

  # Shodan hands us hostnames nobody has vetted. The name is resolved once here
  # and every request to the candidate then connects to the address returned,
  # so a later DNS answer cannot move us inside our own network.
  #
  # An instance reachable under more than one name links its repositories to
  # the name it is configured with, so that name is the one reported. Repository
  # urls are only followed one step and only to a name that passes the same
  # checks as one from shodan.
  def probe(domain, follow_alias: true)
    addresses = resolved_addresses(domain)
    return reject(domain, :unresolved) if addresses.empty?
    return reject(domain, :unroutable) if addresses.any? { |address| unroutable?(address) }

    address = (addresses.find(&:ipv4?) || addresses.first).to_s
    url, robots = reachable(domain, address)
    return reject(domain, :unreachable) if url.nil?

    site = Site.new(domain: domain, url: url, address: address,
                    robots_txt: (robots.body if robots.success?))
    return reject(domain, :disallowed) unless crawlable?(site)

    candidate = gitea_candidate(site) || gitlab_candidate(site)
    return reject(domain, site.forge ? :no_public_repositories : :not_a_forge) if candidate.nil?

    canonical = candidate.canonical_domain
    return candidate if canonical.nil? || canonical == domain
    return reject(domain, :alias_chain) unless follow_alias
    return reject(domain, :alias_of_known) if known_domain?(canonical)

    probe(canonical, follow_alias: false)
  end

  # Plain http is only tried when the https connection is refused. A timeout
  # can be a passing problem with an https instance whose port 80 only
  # redirects, which would otherwise be cached as not being a forge.
  # The robots.txt response doubles as the check that anything answers at all.
  def reachable(domain, address)
    url = "https://#{domain}"
    [url, request("#{url}/robots.txt", address: address)]
  rescue *IGNORABLE_EXCEPTIONS => e
    return nil unless e.is_a?(Faraday::ConnectionFailed) && e.wrapped_exception.is_a?(Errno::ECONNREFUSED)

    url = "http://#{domain}"
    response = get("#{url}/robots.txt", address: address)
    [url, response] if response
  end

  # Domains that fail a probe are skipped on later runs until the entry
  # expires. Failures that are likely to clear up expire before the next
  # monthly run, the rest are rechecked twice a year.
  def reject(domain, reason)
    @rejections[reason] += 1
    ttl = TRANSIENT_REJECTIONS.include?(reason) ? TRANSIENT_REJECTION_TTL : REJECTION_TTL
    REDIS.set(rejection_key(domain), reason, ex: ttl.to_i)
    nil
  end

  def recently_rejected?(domain)
    REDIS.exists?(rejection_key(domain))
  end

  def rejection_key(domain)
    "#{REJECTION_KEY_PREFIX}#{domain}"
  end

  # Gitea and forgejo share the same api, only forgejo answers on its own
  # versioned namespace.
  def gitea_candidate(site)
    version = version_from(site, GITEA_VERSION_PATH)
    return nil if version.blank?

    site.forge = true
    body = site_json(site, GITEA_REPOSITORIES_PATH)
    repository = Array(body['data']).first if body.is_a?(Hash)
    return nil unless repository.is_a?(Hash)

    kind = version_from(site, FORGEJO_VERSION_PATH).present? ? 'forgejo' : 'gitea'
    Candidate.new(domain: site.domain, url: site.url, kind: kind, version: version,
                  canonical_domain: normalize_domain(repository['html_url']))
  end

  # Listing projects anonymously is the thing we need from gitlab, so it doubles
  # as the check that this is a gitlab instance worth indexing. Gitlab will not
  # report its version without a token, so it stays blank until one is
  # configured for the host.
  def gitlab_candidate(site)
    projects = site_json(site, GITLAB_PROJECTS_PATH)
    site.forge ||= projects.is_a?(Array)
    project = projects.first if projects.is_a?(Array)
    return nil unless project.is_a?(Hash)

    Candidate.new(domain: site.domain, url: site.url, kind: 'gitlab', version: nil,
                  canonical_domain: normalize_domain(project['web_url']))
  end

  def version_from(site, path)
    body = site_json(site, path)
    body.is_a?(Hash) ? body['version'].presence : nil
  end

  def site_json(site, path)
    get_json("#{site.url}#{path}", address: site.address)
  end

  # Only a site that turns crawlers away entirely is skipped. Rules on api
  # paths alone are ignored, gitlab's stock robots.txt disallows /api/v*.
  def crawlable?(site)
    site.robots_txt.blank? || RobotsTxtParser.new(site.robots_txt).can_crawl?('/', user_agent)
  end

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

  def get_json(url, params = {}, address: nil)
    response = get(url, params, address: address)
    return nil if response.nil? || !response.success?

    parse_json(response.body)
  end

  def get(url, params = {}, address: nil)
    request(url, params, address: address)
  rescue *IGNORABLE_EXCEPTIONS
    nil
  end

  def request(url, params = {}, address: nil)
    connection(address).get(url) do |req|
      req.params.update(params.stringify_keys) if params.present?
      req.options.timeout = TIMEOUT
      req.options.open_timeout = TIMEOUT
      req.headers['User-Agent'] = user_agent
    end
  end

  def parse_json(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    nil
  end

  # Redirects are deliberately not followed. Every request made here is driven
  # by a hostname shodan supplied, so a Location header would be an easy way to
  # move us onto an address that was never checked.
  #
  # Requests to a candidate connect to the address it was vetted at. Net::HTTP
  # still sends the hostname for SNI and verifies the certificate against it.
  # A proxy from the environment would resolve the name again, so none is used.
  def connection(address = nil)
    @connections ||= {}
    @connections[address] ||= Faraday.new do |conn|
      if address
        conn.proxy = nil
        conn.adapter(:net_http) { |http| http.ipaddr = address }
      else
        conn.adapter Faraday.default_adapter
      end
    end
  end

  def user_agent
    ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
  end
end
