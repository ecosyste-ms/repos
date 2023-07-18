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
end
