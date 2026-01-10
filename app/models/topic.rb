class Topic < ApplicationRecord
  belongs_to :host

  validates :name, presence: true, uniqueness: { scope: :host_id }

  scope :by_count, -> { order(repositories_count: :desc) }
  scope :alphabetical, -> { order(:name) }

  def repositories
    host.repositories.topic(name)
  end

  def to_param
    name
  end

  def self.sync_for_host(host, limit: nil)
    sql = <<~SQL
      SELECT unnest(topics) AS topic_name, COUNT(*) AS cnt
      FROM repositories
      WHERE host_id = ?
        AND topics IS NOT NULL
        AND array_length(topics, 1) > 0
      GROUP BY topic_name
      ORDER BY cnt DESC
    SQL
    sql += " LIMIT #{limit.to_i}" if limit

    results = connection.select_all(sanitize_sql_array([sql, host.id]))

    count = 0
    results.each do |row|
      topic = find_or_initialize_by(host: host, name: row['topic_name'])
      topic.repositories_count = row['cnt']
      topic.save!
      count += 1
    end

    count
  end

  def self.sync_all(limit_per_host: nil)
    Host.find_each do |host|
      puts "Syncing topics for #{host.name}..."
      count = sync_for_host(host, limit: limit_per_host)
      puts "  #{count} topics synced"
    end
  end
end
