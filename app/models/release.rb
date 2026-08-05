class Release < ApplicationRecord
  belongs_to :repository

  def self.backfill_immutability(batch_size: 10_000, after_id: 0)
    raise ArgumentError, 'batch_size must be greater than zero' unless batch_size.positive?

    scanned = 0
    repositories_synced = 0
    cursor = after_id

    loop do
      rows = []
      where('id > ?', cursor)
        .order('releases.id')
        .limit(batch_size)
        .select('releases.id', 'releases.repository_id', 'releases.immutable')
        .each_row(block_size: [batch_size, 1_000].min) do |row|
          rows << [row['id'].to_i, row['repository_id'].to_i, row['immutable']]
        end

      break if rows.empty?

      cursor = rows.last.first
      repository_ids = rows.filter_map do |_id, repository_id, immutable|
        repository_id if immutable.nil?
      end.uniq
      repositories = Repository.includes(:host).where(id: repository_ids).index_by(&:id)

      repository_ids.each do |repository_id|
        repository = repositories[repository_id]
        next unless repository&.host&.kind == 'github'

        repository.download_releases
        repositories_synced += 1
      end

      scanned += rows.size
      yield(scanned, repositories_synced, cursor) if block_given?
    end

    [scanned, repositories_synced, cursor]
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
