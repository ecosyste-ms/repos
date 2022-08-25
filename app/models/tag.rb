class Tag < ApplicationRecord
  belongs_to :repository
  validates_presence_of :name, :sha, :repository
  validates_uniqueness_of :name, scope: :repository_id

  scope :published, -> { where('published_at IS NOT NULL') }

  def to_s
    number
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

  # def repository_url
  #   case repository.host_type
  #   when 'GitHub'
  #     "#{repository.url}/releases/tag/#{name}"
  #   when 'GitLab'
  #     "#{repository.url}/tags/#{name}"
  #   when 'Bitbucket'
  #     "#{repository.url}/commits/tag/#{name}"
  #   end
  # end

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
end
