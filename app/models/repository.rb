class Repository < ApplicationRecord
  include EcosystemApiClient
  
  belongs_to :host
  counter_culture :host, execute_after_commit: true

  has_many :manifests, dependent: :destroy
  has_many :tags, dependent: :delete_all
  has_many :releases, dependent: :delete_all

  has_many :repository_usages, dependent: :delete_all
  has_one :scorecard, dependent: :destroy

  scope :owner, ->(owner) { where(owner: owner) }
  scope :subgroup, ->(owner, subgroup) { where(owner: owner).where("lower(full_name) ilike ?", "#{owner}/#{subgroup}/%") }
  scope :language, ->(language) { where(language: language) }
  scope :forked, ->(fork) { where(fork: fork) }
  scope :archived, ->(archived) { where(archived: archived) }
  scope :active, -> { archived(false) }
  scope :source, -> { forked(false) }
  scope :no_topic, -> { where("topics = '{}'") }
  scope :with_topics, -> { where("topics != '{}'") }
  scope :topic, ->(topic) { where("topics @> ARRAY[?]::varchar[]", topic) }
  scope :with_commit_stats, -> { where("length(commit_stats::text) > 2") }
  scope :starred, -> { where("stargazers_count > 0") }
  scope :minimum_stars, ->(stars) { where("stargazers_count >= ?", stars) }

  scope :created_after, ->(date) { where("created_at > ?", date) }
  scope :updated_after, ->(date) { where("updated_at > ?", date) }

  scope :with_manifests, -> { joins(:manifests).group(:id) }
  scope :without_manifests, -> { includes(:manifests).where(manifests: {repository_id: nil}) }

  scope :with_funding, -> { where("metadata->'funding' is not null") }

  scope :with_metadata, -> { where("length(metadata::text) > 2") }
  scope :has_scorecard, -> { joins(:scorecard) }

  self.record_timestamps = false

  def self.blocked_topics
    return [] unless ENV['BLOCKED_TOPICS'].present?
    ENV['BLOCKED_TOPICS'].split(',').map(&:strip)
  end

  def self.topics
    if self == Repository
      Rails.cache.fetch("topics", expires_in: 1.week) do
        Repository.connection.select_rows("SELECT topics, COUNT(topics) AS topics_count FROM (SELECT id, unnest(topics) AS topics FROM repositories WHERE topics IS NOT NULL AND array_length(topics, 1) > 0) AS foo GROUP BY topics ORDER BY topics_count DESC, topics ASC LIMIT 50000;")
      end
    else
      Rails.cache.fetch("host/#{id}/topics", expires_in: 1.week) do
        Repository.connection.select_rows("SELECT topics, COUNT(topics) AS topics_count FROM (SELECT id, unnest(topics) AS topics FROM repositories WHERE topics IS NOT NULL AND array_length(topics, 1) > 0) AS foo GROUP BY topics ORDER BY topics_count DESC, topics ASC LIMIT 50000;")
      end
    end
  end

  def self.parse_dependencies_async
    Repository.where.not(dependency_job_id: nil).limit(2000).select("id, dependencies_parsed_at").each(&:parse_dependencies_async)
    return if Sidekiq::Queue.new("dependencies").size > 2_000
    Repository.where(status: nil)
      .where(fork: false)
      .where(dependencies_parsed_at: nil, dependency_job_id: nil)
      .select("id, dependencies_parsed_at")
      .limit(2000).each(&:parse_dependencies_async)
  end

  def self.download_tags_async
    return if Sidekiq::Queue.new("tags").size > 5_000
    Repository.where(fork: false, status: nil)
      .order("tags_last_synced_at ASC nulls first")
      .limit(5_000)
      .select("id")
      .each(&:download_tags_async)
  end

  def self.update_metadata_files_async
    return if Sidekiq::Queue.new("default").size > 10_000
    Repository.where(status: nil, fork: false)
      .where("length(metadata::text) = 2")
      .limit(5_000)
      .select("id")
      .each(&:update_metadata_files_async)
  end

  def sync_owner
    return if owner_record&.hidden?
    host.sync_owner(owner) if owner_record.nil?
  end

  def sync_owner_async
    return if owner_record&.hidden?
    host.sync_owner_async(owner) if owner_record.nil?
  end

  def has_scorecard?
    Scorecard.exists?(repository_id: id)
  end

  def owner_record
    @owner_record ||= host.owners.find_by("lower(login) = ?", owner.downcase)
  end

  def owner
    read_attribute(:owner) || full_name.split("/").first
  end

  def to_s
    full_name
  end

  def to_param
    full_name
  end

  def id_or_name
    uuid || full_name
  end

  def subgroups
    return [] if full_name.split("/").size < 3
    full_name.split("/")[1..-2]
  end

  def project_slug
    full_name.split("/").last
  end

  def project_name
    full_name.split("/")[1..-1].join("/")
  end

  def sync(force: false)
    return if host.nil?
    return if owner_record&.hidden?

    if !force && last_synced_at && last_synced_at > 1.week.ago
      # if recently synced, schedule for syncing 1 day later
      delay = (last_synced_at + 1.day) - Time.now
      UpdateRepositoryWorker.perform_in(delay, id)
      return
    end
    host.host_instance.update_from_host(self)
  end

  def sync_async(force = false)
    UpdateRepositoryWorker.perform_async(id, force)
  end

  def html_url
    host.html_url(self)
  end

  def download_url(branch = default_branch, kind = "branch")
    host.download_url(self, branch, kind)
  end

  def icon_url(size = nil)
    host.avatar_url(self, size)
  end

  def blob_url(sha = nil)
    sha ||= default_branch
    host.blob_url(self, sha)
  end

  def parse_dependencies_async
    ParseDependenciesWorker.perform_async(id)
  end

  def parse_dependencies
    connection = ecosystem_connection(PARSER_DOMAIN)

    res = if dependency_job_id
      connection.get("/api/v1/jobs/#{dependency_job_id}")
    else
      connection.post("/api/v1/jobs?url=#{CGI.escape(download_url)}")
    end
    if res.success?
      json = Oj.load(res.body)
      record_dependency_parsing(json)
    end
  end

  def record_dependency_parsing(json)
    if ["complete", "error"].include?(json["status"])
      if json["status"] == "complete"
        new_manifests = json["results"].to_h.with_indifferent_access["manifests"]

        if new_manifests.blank?
          manifests.each(&:destroy)
        else
          new_manifests.each { |m| sync_manifest(m) }
          delete_old_manifests(new_manifests)
        end
      end

      update_columns(dependencies_parsed_at: Time.now, dependency_job_id: nil)
      RepositoryUsage.from_repository(self)
    else
      update_column(:dependency_job_id, json["id"]) if dependency_job_id != json["id"]
      ParseDependenciesWorker.perform_in(10.minutes, id)
    end
  end

  def sync_manifest(m)
    args = {ecosystem: m[:platform] || m[:ecosystem], kind: m[:kind], filepath: m[:path], sha: m[:sha]}

    unless manifests.find_by(args)
      manifest = manifests.create(args)
      return if m[:dependencies].nil?
      dependencies = m[:dependencies].compact.map(&:with_indifferent_access).uniq { |dep| [dep[:name].try(:strip), dep[:requirement], dep[:type]] }

      deps = dependencies.map do |dep|
        ecosystem = manifest.ecosystem
        next unless dep.is_a?(Hash)
        next unless dep[:name].present?
        {
          manifest_id: manifest.id,
          package_name: dep[:name].to_s.strip[0..255],
          ecosystem: ecosystem,
          requirements: dep[:requirement],
          kind: dep[:type],
          repository_id: id,
          direct: manifest.kind == "manifest",
          created_at: Time.now,
          updated_at: Time.now
        }
      end.compact

      Dependency.insert_all(deps) if deps.any?
    end
  end

  def delete_old_manifests(new_manifests)
    existing_manifests = manifests.map { |m| [m.ecosystem, m.filepath] }
    to_be_removed = existing_manifests - new_manifests.map { |m| [m[:platform] || m[:ecosystem], m[:path]] }
    to_be_removed.each do |m|
      manifests.where(ecosystem: m[0], filepath: m[1]).each(&:destroy)
    end
    manifests.where.not(id: manifests.latest.map(&:id)).each(&:destroy)
  end

  def latest_tag
    @latest_tag ||= tags.order("published_at desc nulls last").first
  end

  def set_latest_tag_published_at
    self.latest_tag_published_at = (latest_tag.try(:published_at).presence || updated_at)
  end

  def set_latest_tag_name
    self.latest_tag_name = latest_tag.try(:name)
  end

  def self.sync_extra_details_async
    Repository.where(files_changed: true, fork: false).limit(600).order("pushed_at asc").select("id").each(&:sync_extra_details_async)
  end

  def sync_extra_details_async
    SyncExtraDetailsWorker.perform_async(id)
  end

  def sync_extra_details(force: false)
    return if owner_record&.hidden?
    return if fork? && !force
    return unless files_changed? || force
    if pushed_at.present? || force
      parse_dependencies unless dependencies_parsed_at.present? && dependencies_parsed_at > pushed_at
      update_metadata_files
      download_tags
      parse_dependencies if dependency_job_id.present?
      sync_scorecard_async
      # sync_commit_stats
    end
    update(files_changed: false)
  end

  def get_file_contents(path)
    host.get_file_contents(self, path)
  end

  def get_file_list
    host.get_file_list(self)
  end

  def download_tags
    host.download_tags(self)
    host.download_releases(self) if tags_count && tags_count > 0
    cleanup_duplicate_releases
  end

  def download_releases
    host.download_releases(self)
  end

  def download_tags_async
    DownloadTagsWorker.perform_async(id)
  end

  def archive_list
    Oj.load(Faraday.get(archive_list_url).body)
  rescue
    []
  end

  def archive_contents(path)
    Oj.load(Faraday.get(archive_contents_url(path)).body)
  rescue
    {}
  end

  def archive_list_url
    "#{ARCHIVES_DOMAIN}/api/v1/archives/list?url=#{CGI.escape(download_url)}"
  end

  def archive_contents_url(path)
    "#{ARCHIVES_DOMAIN}/api/v1/archives/contents?url=#{CGI.escape(download_url)}&path=#{path}"
  end

  def archive_basename
    default_branch
  end

  def package_usages
    PackageUsage.host(host.name).repo_uuid(uuid)
  end

  def fetch_metadata_files_list
    file_list = get_file_list
    return if file_list.blank?
    {
      readme: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?README/i) },
      changelog: file_list.find { |file| file.match(/^CHANGE|^HISTORY|^NEWS/i) },
      contributing: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?CONTRIBUTING/i) },
      funding: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?FUNDING\.ya?ml/i)},
      license: file_list.find { |file| file.match(/^LICENSE|^COPYING|^MIT-LICENSE/i) },
      code_of_conduct: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?CODE[-_]OF[-_]CONDUCT/i) },
      threat_model: file_list.find { |file| file.match(/^THREAT[-_]MODEL/i) },
      audit: file_list.find { |file| file.match(/^AUDIT/i) },
      citation: file_list.find { |file| file.match(/^CITATION/i) },
      codeowners: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?CODEOWNERS/i) },
      security: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?SECURITY/i) },
      support: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?SUPPORT/i) },
      governance: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?GOVERNANCE/i) },
      roadmap: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?ROADMAP/i) },
      authors: file_list.find { |file| file.match(/^AUTHORS/i) },
      dei: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?DEI/i) },
      publiccode: file_list.find { |file| file.match(/^publiccode.ya?ml/i) },
      codemeta: file_list.find { |file| file.match(/^codemeta.json/i) },
      zenodo: file_list.find { |file| file.match(/^.zenodo.json/i) },
      notice: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?NOTICE(?:\.(md|txt))?$/i) },
      maintainers: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?MAINTAINERS(?:\.(md|txt))?$/i) },
      copyright: file_list.find { |file| file.match(/^COPYRIGHT(?:\.(md|txt))?$/i) },
      agents: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?AGENTS\.md$/i) },
      dco: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?DCO(?:\.(md|txt))?$/i) },
      cla: file_list.find { |file| file.match(/^(docs\/)?(.github\/)?(.gitlab\/)?(CLA|CONTRIBUTOR[-_ ]LICENSE[-_ ]AGREEMENT)(?:\.(md|txt))?$/i) }
    }
  end

  def update_metadata_files_async
    UpdateMetadataFilesWorker.perform_async(id)
  end

  def update_metadata_files
    metadata_files = fetch_metadata_files_list
    return if metadata_files.nil?
    metadata["files"] = metadata_files
    save
    parse_funding
  end

  def parse_funding
    if related_dot_github_repo.present? && related_dot_github_repo.metadata["funding"].present?
      metadata["funding"] = related_dot_github_repo.metadata["funding"]
    else
      return if metadata["files"]["funding"].blank?
      file = get_file_contents(metadata["files"]["funding"])
      return if file.blank?
      metadata["funding"] = YAML.load(file[:content])
    end
    save
  rescue
    nil # invalid yaml
  end

  def related_dot_github_repo
    return nil if project_name == ".github"
    host.find_repository("#{owner}/.github")
  end

  def funding_links
    (repo_funding_links + owner_funding_links).uniq
  end

  def owner_funding_links
    owner_record.try(:funding_links) || []
  end

  def repo_funding_links
    return [] if metadata.blank? || metadata["funding"].blank?
    return [] unless metadata["funding"].is_a?(Hash)
    metadata["funding"].map do |key, v|
      next if v.blank?
      case key
      when "github"
        Array(v).map { |username| "https://github.com/sponsors/#{username}" }
      when "tidelift"
        "https://tidelift.com/funding/github/#{v}"
      when "community_bridge"
        "https://funding.communitybridge.org/projects/#{v}"
      when "issuehunt"
        "https://issuehunt.io/r/#{v}"
      when "open_collective"
        "https://opencollective.com/#{v}"
      when "ko_fi"
        "https://ko-fi.com/#{v}"
      when "liberapay"
        "https://liberapay.com/#{v}"
      when "custom"
        v
      when "otechie"
        "https://otechie.com/#{v}"
      when "patreon"
        "https://patreon.com/#{v}"
      when "polar"
        "https://polar.sh/#{v}"
      when "buy_me_a_coffee"
        "https://buymeacoffee.com/#{v}"
      when 'thanks_dev'
        "https://thanks.dev/#{v}"
      else
        v
      end
    end.flatten.compact
  end

  def ping_packages_async
    PingPackagesWorker.perform_async(id)
  end

  def ping_packages
    ecosystem_connection(PACKAGES_DOMAIN).get("/api/v1/packages/ping?repository_url=#{html_url}")
  end

  def commits_url
    "#{COMMITS_DOMAIN}/hosts/#{host.name}/repositories/#{full_name}"
  end

  def commits_api_url
    "#{COMMITS_DOMAIN}/api/v1/hosts/#{host.name}/repositories/#{full_name}"
  end

  def sync_commit_stats
    url_path = commits_api_url.gsub(COMMITS_DOMAIN, '')
    response = ecosystem_connection(COMMITS_DOMAIN).get(url_path)
    return if response.status != 200
    stats = Oj.load(response.body)
    return if stats.blank?
    return if stats["total_commits"].nil?
    self.commit_stats = stats.slice("total_commits", "total_committers", "mean_commits", "dds", "last_synced_commit")
    save
  end

  def sync_commit_stats_async
    SyncCommitStatsWorker.perform_async(id)
  end

  def self.parse_dependencies_for_github_actions_tags
    conn = ecosystem_connection(PACKAGES_DOMAIN)

    repo_names = Set.new

    response = conn.get("/api/v1/registries/github%20actions/packages?sort=updated_at&order=desc")
    return nil unless response.success?

    links = parse_link_header(response.headers)

    while links["next"].present?
      json = response.body.is_a?(String) ? Oj.load(response.body) : response.body

      json.each do |package|
        repo_names << package["name"]
      end

      response = conn.get(links["next"].gsub(PACKAGES_DOMAIN, ''))
      return nil unless response.success?
      links = parse_link_header(response.headers)
    end

    # Process the final page
    json = response.body.is_a?(String) ? Oj.load(response.body) : response.body
    json.each do |package|
      repo_names << package["name"]
    end

    host = Host.find_by_name("GitHub")

    repo_names.each do |repo_name|
      repo = host.find_repository(repo_name)
      if repo.nil?
        host.sync_repository_async(repo_name)
        next
      end
      repo.download_tags
      repo.tags.each do |tag|
        tag.parse_dependencies_async if tag.dependencies_parsed_at.nil?
      end
    end
  end

  def self.parse_link_header(headers)
    return {} unless headers["Link"].present?

    links = headers["Link"].split(",").map do |link|
      url, rel = link.split(";")
      url = url[/<(.*)>/, 1]
      rel = rel[/rel="(.*)"/, 1]
      [rel, url]
    end

    Hash[links]
  end

  def cleanup_duplicate_releases
    releases.group(:uuid).having("count(*) > 1").count.each do |uuid, count|
      releases.where(uuid: uuid).order("created_at desc").offset(1).each(&:destroy)
    end
  end

  def purl
    PackageURL.new(
      type: host.host_instance.purl_type,
      namespace: owner,
      name: project_slug
    ).to_s
  end
  
  def convert_purl_type(purl_type)
    case purl_type
    when "actions"
      "githubactions"
    when "elpa"
      "melpa"
    when "go"
      "golang"
    when "homebrew"
      "brew"
    when "packagist"
      "composer"
    when "rubygems"
      "gem"
    when "swiftpm"
      "swift"
    else
      purl_type
    end
  end

  def sbom
    {
      bomFormat: "CycloneDX",
      specVersion: "1.5",
      version: 1,
      serialNumber: "urn:uuid:#{SecureRandom.uuid}",
      metadata: {
        timestamp: Time.now.utc.iso8601,
        tools: [
          {
            vendor: "Ecosystems",
            name: "Ecosystems SBOM Generator"
          }
        ],
        component: {
          type: "application",
          name: full_name
        }
      },
      components: manifests.includes(:dependencies).flat_map do |manifest|
        manifest.dependencies.map do |dep|
          {
            type: "library",
            name: dep.package_name,
            version: dep.requirements,
            purl: "pkg:#{convert_purl_type(dep.ecosystem)}/#{dep.package_name}",
            properties: [
              {
                name: "filePath",
                value: manifest.filepath
              }
            ]
          }.compact
        end
      end.uniq
    }
  end

  def owner_hidden?
    return false if owner.blank?
    owner_record&.hidden? == true
  end

  def has_blocked_topic?
    return false if topics.blank?
    return false if self.class.blocked_topics.empty?

    (topics & self.class.blocked_topics).any?
  end

  def sync_scorecard
    Scorecard.lookup(self)
  end

  def sync_scorecard_async
    SyncScorecardWorker.perform_async(id)
  end
end
