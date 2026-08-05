class Release < ApplicationRecord
  belongs_to :repository

  def self.backfill_immutability(repository_names:, block_size: 1_000, after_name: nil)
    raise ArgumentError, 'block_size must be greater than zero' unless block_size.positive?

    host = Host.find_by_name('GitHub')
    return [0, 0, 0, after_name] unless host

    names = repository_names.compact.uniq.sort_by(&:downcase)
    names = names.drop_while { |name| name.downcase <= after_name.downcase } if after_name.present?
    processed = 0
    repositories_synced = 0
    repositories_missing = 0
    last_name = after_name

    names.each do |name|
      repository = host.find_repository(name)
      if repository
        needs_backfill = false
        repository.releases.select(:immutable).each_row(block_size: block_size) do |row|
          needs_backfill = true if row['immutable'].nil?
        end

        if needs_backfill
          repository.download_releases
          repositories_synced += 1
        end
      else
        repositories_missing += 1
      end

      processed += 1
      last_name = name
      if block_given? && (processed == 1 || (processed % 100).zero?)
        yield(processed, repositories_synced, repositories_missing, last_name)
      end
    end

    [processed, repositories_synced, repositories_missing, last_name]
  end

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
    @clean_number ||= begin
      cleaned = SemanticRange.clean(number) || number
      cleaned.gsub(/(\.|^)0+([1-9]\d*)/, '\1\2') # Remove leading zeros
    end
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
