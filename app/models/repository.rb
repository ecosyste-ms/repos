class Repository < ApplicationRecord
  belongs_to :host

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

  def self.parse_dependencies_async
    Repository.where.not(dependency_job_id: nil).limit(5000).select('id, dependencies_parsed_at').each(&:parse_dependencies_async)
    Repository.where(status: nil)
              .where(fork: false)
              .where(dependencies_parsed_at: nil, dependency_job_id: nil)
              .select('id, dependencies_parsed_at')
              .limit(4000).each(&:parse_dependencies_async)
  end

  def self.download_tags_async
    Repository.where(fork: false, status: nil).order('tags_last_synced_at ASC nulls first').limit(10_000).select('id').each(&:download_tags_async)
  end

  def self.update_package_usages_async
    return if Sidekiq::Queue.new('usage').size > 10_000
    Repository.where(fork: false, status: nil).order('usage_updated_at ASC nulls first').limit(5_000).select('id').each do |repo|
      PackageUsageWorker.perform_async(repo.id)
    end
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

  def project_name
    full_name.split('/')[1..-1].join('/')
  end

  def sync
    host.host_instance.update_from_host(self)
  end

  def sync_async
    UpdateRepositoryWorker.perform_async(self.id)
  end

  def html_url
    host.html_url(self)
  end

  def download_url(branch = default_branch, kind = 'branch')
    host.download_url(self, branch, kind)
  end

  def avatar_url(size)
    host.avatar_url(self, size)
  end

  def blob_url(sha = nil)
    sha ||= default_branch
    host.blob_url(self, sha = nil)
  end

  def parse_dependencies_async
    return if dependencies_parsed_at.present? # temp whilst backfilling db
    ParseDependenciesWorker.perform_async(self.id)
  end

  def parse_dependencies
    connection = Faraday.new(url: "https://parser.ecosyste.ms") do |faraday|
      faraday.use Faraday::FollowRedirects::Middleware
    
      faraday.adapter Faraday.default_adapter
    end

    if dependency_job_id
      res = connection.get("/api/v1/jobs/#{dependency_job_id}")
    else  
      res = connection.post("/api/v1/jobs?url=#{CGI.escape(download_url)}")
    end
    if res.success?
      json = Oj.load(res.body)
      record_dependency_parsing(json)
    end
  end

  def record_dependency_parsing(json)
    if ['complete', 'error'].include?(json['status'])
      if json['status'] == 'complete'
        new_manifests = json['results'].to_h.with_indifferent_access['manifests']
        
        if new_manifests.blank?
          manifests.each(&:destroy)
        else
          new_manifests.each {|m| sync_manifest(m) }
          delete_old_manifests(new_manifests)
        end
      end

      update_columns(dependencies_parsed_at: Time.now, dependency_job_id: nil)
    else
      update_column(:dependency_job_id, json["id"]) if dependency_job_id != json["id"]
    end
  end

  def sync_manifest(m)
    args = {ecosystem: (m[:platform] || m[:ecosystem]), kind: m[:kind], filepath: m[:path], sha: m[:sha]}

    unless manifests.find_by(args)
      return unless m[:dependencies].present? && m[:dependencies].any?
      manifest = manifests.create(args)
      dependencies = m[:dependencies].map(&:with_indifferent_access).uniq{|dep| [dep[:name].try(:strip), dep[:requirement], dep[:type]]}

      deps = dependencies.map do |dep|
        ecosystem = manifest.ecosystem
        next unless dep.is_a?(Hash)

        {
          manifest_id: manifest.id,
          package_name: dep[:name].try(:strip),
          ecosystem: ecosystem,
          requirements: dep[:requirement],
          kind: dep[:type],
          repository_id: self.id,
          direct: manifest.kind == 'manifest',
          created_at: Time.now,
          updated_at: Time.now
        }
      end.compact

      Dependency.insert_all(deps)
    end
  end

  def delete_old_manifests(new_manifests)
    existing_manifests = manifests.map{|m| [m.ecosystem, m.filepath] }
    to_be_removed = existing_manifests - new_manifests.map{|m| [(m[:platform] || m[:ecosystem]), m[:path]] }
    to_be_removed.each do |m|
      manifests.where(ecosystem: m[0], filepath: m[1]).each(&:destroy)
    end
    manifests.where.not(id: manifests.latest.map(&:id)).each(&:destroy)
  end

  def get_file_contents(path)
    host.get_file_contents(self, path)
  end

  def get_file_list
    host.get_file_list(self)
  end

  def download_tags
    host.download_tags(self)
  end

  def download_tags_async
    DownloadTagsWorker.perform_async(self.id)
  end

  def archive_list
    begin
      Oj.load(Faraday.get(archive_list_url).body)
    rescue
      []
    end
  end

  def archive_contents(path)
    begin
      Oj.load(Faraday.get(archive_contents_url(path)).body)
    rescue
      {}
    end
  end

  def archive_list_url
    "https://archives.ecosyste.ms/api/v1/archives/list?url=#{CGI.escape(download_url)}"
  end

  def archive_contents_url(path)
    "https://archives.ecosyste.ms/api/v1/archives/contents?url=#{CGI.escape(download_url)}&path=#{path}"
  end

  def archive_basename
    default_branch
  end
end
