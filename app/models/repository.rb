class Repository < ApplicationRecord
  belongs_to :host
  counter_culture :host
  has_many :manifests, dependent: :destroy
  has_many :dependencies
  has_many :tags

  scope :owner, ->(owner) { where(owner: owner) }
  scope :language, ->(main_language) { where(main_language: main_main_language) }
  scope :fork, ->(fork) { where(fork: fork) }
  scope :archived, ->(archived) { where(archived: archived) }
  scope :active, -> { archived(false) }
  scope :source, -> { fork(false) }
  scope :no_topic, -> { where("topics = '{}'") }
  scope :topic, ->(topic) { where("topics @> ARRAY[?]::varchar[]", topic) }
  
  scope :with_manifests, -> { joins(:manifests).group(:id) }
  scope :without_manifests, -> { includes(:manifests).where(manifests: {repository_id: nil}) }

  def self.download_async(full_name_or_id, discovered: false)
    RepositoryDownloadWorker.perform_async(full_name_or_id, discovered)
  end

  def self.download(full_name_or_id, discovered: false)
    begin
      remote_repo = Issue.github_client.repo(full_name_or_id, accept: 'application/vnd.github.drax-preview+json,application/vnd.github.mercy-preview+json')
      repo = update_from_github(remote_repo)
      repo.update_column(:discovered, true) if repo && discovered
    rescue Octokit::NotFound
      if full_name_or_id.is_a?(String)
        Repository.find_by_full_name(full_name_or_id).try(:destroy)
      else
        Repository.find_by_github_id(full_name_or_id).try(:destroy)
      end
    rescue Octokit::InvalidRepository
      # full_name isn't a proper repo name
    rescue Octokit::RepositoryUnavailable, Octokit::UnavailableForLegalReasons
      # repo locked/disabled
      if full_name_or_id.is_a?(String)
        repo = Repository.find_by_full_name(full_name_or_id)
      else
        repo = Repository.find_by_github_id(full_name_or_id)
      end
      repo.update_columns({ last_sync_at: Time.zone.now, discovered: discovered }) if repo
    end
  end

  def self.download_if_missing_and_active(name)
    return if name.to_s.blank?
    r = Repository.where('full_name ilike ?', name.to_s).first
    unless r
      begin
        remote_repo = Issue.github_client.repo(name)
        if remote_repo.fork || remote_repo.archived
          puts "SKIPPING #{name} - fork:#{remote_repo.fork} archived:#{remote_repo.archived}"
        else
          Repository.update_from_github(remote_repo)
        end
      rescue Octokit::NotFound, Octokit::InvalidRepository
        # not found or invalid
      end
    end
  end

  def self.update_from_github(remote_repo)
    begin
      repo = Repository.find_or_create_by(github_id: remote_repo.id)
      repo.full_name = remote_repo.full_name
      repo.created_at = remote_repo.created_at
      repo.updated_at = remote_repo.updated_at
      repo.owner = remote_repo.full_name.split('/').first
      repo.main_language = remote_repo.language
      repo.archived = remote_repo.archived
      repo.fork = remote_repo.fork
      repo.description = remote_repo.description
      repo.pushed_at = remote_repo.pushed_at
      repo.size = remote_repo.size
      repo.stargazers_count = remote_repo.stargazers_count
      repo.open_issues_count = remote_repo.open_issues_count
      repo.forks_count = remote_repo.forks_count
      repo.subscribers_count = remote_repo.subscribers_count
      repo.default_branch = remote_repo.default_branch
      repo.topics = remote_repo.topics
      repo.last_sync_at = Time.now
      sync_files = repo.pushed_at_changed?
      repo.save
      if !repo.fork? && !repo.archived? && sync_files
        repo.download_manifests
        repo.update_file_list
        repo.mine_dependencies_async
      end
      repo
    rescue ArgumentError, Octokit::Error
      repo.update_column(:last_sync_at, Time.zone.now) if repo
    end
  end

  def setup_async
    RepoSetupWorker.perform_async(id)
  end

  def setup
    download_tags
    Issue.download(full_name, self.created_at)
  end

  def html_url
    "https://github.com/#{full_name}"
  end

  def blob_url(sha = nil)
    sha ||= default_branch
    "#{html_url}/blob/#{sha}/"
  end

  def file_url(filename, sha = nil)
    sha ||= default_branch
    "#{blob_url(sha)}/#{filename}"
  end

  def new_file_url(filename, branch = nil)
    branch ||= default_branch
    "#{html_url}/new/#{branch}?filename=#{filename}"
  end

  def download_manifests
    file_list = get_file_list
    return if file_list.blank?
    new_manifests = parse_manifests(file_list)

    if new_manifests.blank?
      manifests.each(&:destroy)
      return
    end

    new_manifests.each {|m| sync_manifest(m) }

    delete_old_manifests(new_manifests)
  end

  def parse_manifests(file_list)
    manifest_paths = Bibliothecary.identify_manifests(file_list)

    manifest_paths.map do |manifest_path|
      file = get_file_contents(manifest_path)
      if file.present? && file[:content].present?
        begin
          manifest = Bibliothecary.analyse_file(manifest_path, file[:content]).first
          manifest.merge!(sha: file[:sha]) if manifest
          manifest
        rescue
          nil
        end
      end
    end.reject(&:blank?)
  end

  def sync_manifest(m)
    args = {platform: m[:platform], kind: m[:kind], filepath: m[:path], sha: m[:sha]}

    unless manifests.find_by(args)
      return unless m[:dependencies].present? && m[:dependencies].any?
      manifest = manifests.create(args)
      dependencies = m[:dependencies].map(&:with_indifferent_access).uniq{|dep| [dep[:name].try(:strip), dep[:requirement], dep[:type]]}

      packages = Package.platform(manifest.platform).where(name: dependencies.map{|d| d[:name]})

      deps = dependencies.map do |dep|
        platform = manifest.platform
        next unless dep.is_a?(Hash)

        package = packages.select{|p| p.name == dep[:name] }.first

        {
          manifest_id: manifest.id,
          package_id: package.try(:id),
          package_name: dep[:name].try(:strip),
          platform: platform,
          requirements: dep[:requirement],
          kind: dep[:type],
          repository_id: self.id,
          direct: manifest.kind == 'manifest',
          created_at: Time.now,
          updated_at: Time.now
        }
      end.compact

      RepositoryDependency.insert_all(deps)
    end
  end

  def delete_old_manifests(new_manifests)
    existing_manifests = manifests.map{|m| [m.platform, m.filepath] }
    to_be_removed = existing_manifests - new_manifests.map{|m| [m[:platform], m[:path]] }
    to_be_removed.each do |m|
      manifests.where(platform: m[0], filepath: m[1]).each(&:destroy)
    end
    manifests.where.not(id: manifests.latest.map(&:id)).each(&:destroy)
  end

  def get_file_list
    @file_list ||= begin
      tree = Issue.github_client.tree(full_name, default_branch, :recursive => true).tree
      tree.select{|item| item.type == 'blob' }.map{|file| file.path }
    rescue *IGNORABLE_EXCEPTIONS
      nil
    end
  end

  def get_file_contents(path)
    file = Issue.github_client.contents(full_name, path: path)
    return nil if file.is_a?(Array)
    {
      sha: file.sha,
      content: file.content.present? ? Base64.decode64(file.content) : file.content
    }
  rescue URI::InvalidURIError
    nil
  rescue *IGNORABLE_EXCEPTIONS
    nil
  end

  def update_file_list
    file_list = get_file_list
    return if file_list.nil?
    self.readme_path          = file_list.find{|file| file.match(/^README/i) }
    self.changelog_path       = file_list.find{|file| file.match(/^CHANGE|^HISTORY/i) }
    self.contributing_path    = file_list.find{|file| file.match(/^(docs\/)?(.github\/)?CONTRIBUTING/i) }
    self.license_path         = file_list.find{|file| file.match(/^LICENSE|^COPYING|^MIT-LICENSE/i) }
    self.code_of_conduct_path = file_list.find{|file| file.match(/^(docs\/)?(.github\/)?CODE[-_]OF[-_]CONDUCT/i) }
    self.sol_files            = file_list.any?{|file| file.match(/\.sol$/i) }

    save if self.changed?
  end

  def download_tags
    existing_tag_names = tags.pluck(:name)
    tags = Issue.github_client.refs(full_name, 'tags')
    Array(tags).each do |tag|
      next unless tag && tag.is_a?(Sawyer::Resource) && tag['ref']
      download_tag(tag, existing_tag_names)
    end
    packages.find_each(&:forced_save) if tags.present?
  rescue *IGNORABLE_EXCEPTIONS
    nil
  end

  def download_tag(tag, existing_tag_names)
    match = tag.ref.match(/refs\/tags\/(.*)/)
    return unless match
    name = match[1]
    return if existing_tag_names.include?(name)

    object = Issue.github_client.get(tag.object.url)

    tag_hash = {
      name: name,
      kind: tag.object.type,
      sha: tag.object.sha
    }

    case tag.object.type
    when 'commit'
      tag_hash[:published_at] = object.committer.date
    when 'tag'
      tag_hash[:published_at] = object.tagger.date
    end

    tags.create(tag_hash)
  end

  def sync
    Repository.download(github_id)
    update_score
  end
end
