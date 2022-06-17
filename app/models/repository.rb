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

  def to_s
    full_name
  end

  def to_param
    full_name
  end

  def sync
    host.sync_repository(full_name)
  end

  def sync_async
    host.sync_repository_async(full_name)
  end

  def html_url
    host.html_url(self)
  end

  def avatar_url(size)
    host.avatar_url(self, size)
  end

  def blob_url(sha = nil)
    sha ||= default_branch
    host.blob_url(self, sha = nil)
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
    args = {ecosystem: m[:platform], kind: m[:kind], filepath: m[:path], sha: m[:sha]}

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
    to_be_removed = existing_manifests - new_manifests.map{|m| [m[:platform], m[:path]] }
    to_be_removed.each do |m|
      
      manifests.where(ecosystem: m[0], filepath: m[1]).each(&:destroy)
    end
    manifests.where.not(id: manifests.latest.map(&:id)).each(&:destroy)
  end


  # def update_file_list
  #   file_list = get_file_list
  #   return if file_list.nil?
  #   self.readme_path          = file_list.find{|file| file.match(/^README/i) }
  #   self.changelog_path       = file_list.find{|file| file.match(/^CHANGE|^HISTORY/i) }
  #   self.contributing_path    = file_list.find{|file| file.match(/^(docs\/)?(.github\/)?CONTRIBUTING/i) }
  #   self.license_path         = file_list.find{|file| file.match(/^LICENSE|^COPYING|^MIT-LICENSE/i) }
  #   self.code_of_conduct_path = file_list.find{|file| file.match(/^(docs\/)?(.github\/)?CODE[-_]OF[-_]CONDUCT/i) }

  #   save if self.changed?
  # end

  def get_file_contents(path)
    host.get_file_contents(self, path)
  end

  def get_file_list
    host.get_file_list(self)
  end

  def download_tags
    host.download_tags(self)
  end
end
