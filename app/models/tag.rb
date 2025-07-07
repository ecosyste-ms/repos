class Tag < ApplicationRecord
  include EcosystemApiClient
  
  belongs_to :repository
  counter_culture :repository, execute_after_commit: true

  validates_presence_of :name, :sha, :repository
  validates_uniqueness_of :name, scope: :repository_id

  scope :published, -> { where('published_at IS NOT NULL') }

  has_many :manifests, dependent: :destroy

  def to_s
    name
  end

  def to_param
    name
  end

  def semantic_version
    @semantic_version ||= begin
    Semantic::Version.new(clean_number)
    rescue ArgumentError
      nil
    end
  end

  def greater_than_1?
    return nil unless follows_semver?
    begin
      SemanticRange.gte(clean_number, '1.0.0')
    rescue
      false
    end
  end

  def stable?
    valid_number? && !prerelease?
  end

  def valid_number?
    !!semantic_version
  end

  def follows_semver?
    @follows_semver ||= valid_number?
  end

  def parsed_number
    @parsed_number ||= semantic_version || number
  end

  def clean_number
    @clean_number ||= (SemanticRange.clean(number) || number)
  end

  def <=>(other)
    if parsed_number.is_a?(String) || other.parsed_number.is_a?(String)
      other.number <=> number
    else
      other.parsed_number <=> parsed_number
    end
  end

  def prerelease?
    !!parsed_number.try(:pre)
  end

  def number
    name
  end

  def download_url
    repository.host.download_url(repository, name, 'tag')
  end

  def html_url
    repository.host.tag_url(repository, name)
  end

  def related_tags
    repository.sorted_tags
  end

  def tag_index
    related_tags.index(self)
  end

  def next_tag
    related_tags[tag_index - 1]
  end

  def previous_tag
    related_tags[tag_index + 1]
  end

  def diff_url
    return nil unless repository && previous_tag && previous_tag
    repository.compare_url(previous_tag.number, number)
  end

  def blob_url
    repository.blob_url(name)
  end

  def parse_dependencies_async
    ParseTagDependenciesWorker.perform_async(self.id)
  end

  def parse_dependencies
    connection = ecosystem_connection(PARSER_DOMAIN)

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
      ParseTagDependenciesWorker.perform_in(10.minutes, self.id)
    end
  end

  def sync_manifest(m)
    args = {ecosystem: (m[:platform] || m[:ecosystem]), kind: m[:kind], filepath: m[:path], sha: m[:sha]}

    unless manifests.find_by(args)
      manifest = manifests.create(args)
      return if m[:dependencies].nil?
      dependencies = m[:dependencies].compact.map(&:with_indifferent_access).uniq{|dep| [dep[:name].try(:strip), dep[:requirement], dep[:type]]}

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
          repository_id: self.id,
          direct: manifest.kind == 'manifest',
          created_at: Time.now,
          updated_at: Time.now
        }
      end.compact

      Dependency.insert_all(deps) if deps.any?
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

  def purl
    PackageURL.new(
      type: repository.host.host_instance.purl_type,
      namespace: repository.owner,
      name: repository.project_slug,
      version: name
    ).to_s
  end
end
