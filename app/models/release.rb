class Release < ApplicationRecord
  belongs_to :repository

  def to_s
    name
  end

  def to_param
    tag_name
  end

  def download_url
    repository.host.download_url(repository, tag_name, 'tag')
  end

  def html_url
    repository.host.tag_url(repository, tag_name)
  end

  def related_tag
    repository.tags.find_by(name: tag_name)
  end

  def semantic_version
    @semantic_version ||= begin
    Semantic::Version.new(clean_number)
    rescue ArgumentError
      nil
    end
  end

  def parsed_number
    @parsed_number ||= semantic_version || number
  end

  def clean_number
    @clean_number ||= (SemanticRange.clean(number) || number)
  end

  def number
    tag_name
  end

  def <=>(other)
    if parsed_number.is_a?(String) || other.parsed_number.is_a?(String)
      other.number <=> number
    else
      other.parsed_number <=> parsed_number
    end
  end
end
