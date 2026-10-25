class RepositoryUsageBackfillWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options queue: 'usage', lock: :until_and_while_executing, on_conflict: {client: :log, server: :reschedule}

  BATCH_SIZE = 100

  def self.key(generation = RepositoryUsage.generation)
    "repository_usage_backfill:#{generation}"
  end

  def self.status
    state = REDIS.hgetall(key)
    pending = REDIS.zcard("#{key}:pending")
    state.merge('pending' => pending, 'pending_ids' => REDIS.zrange("#{key}:pending", 0, 9), 'ready' => state['finished'] == 'true' && pending.zero?)
  end

  def self.retry_repository(id, **limits)
    return unless RepositoryUsage.writes_enabled?(id)

    repository = Repository.select(:id).find_by(id: id)
    RepositoryUsage.from_repository(repository, **limits) if repository
    REDIS.zrem("#{key}:pending", id)
    true
  rescue RepositoryUsage::ReadLimitExceeded, RepositoryUsage::InvalidContribution, ActiveRecord::QueryCanceled => error
    record_failure(id, error)
    false
  end

  def self.record_failure(id, error)
    REDIS.zadd("#{key}:pending", id, id)
    Sidekiq.logger.warn("Usage backfill repository #{id}: #{error.class}: #{error.message}")
  end

  def perform(generation)
    return unless RepositoryUsage.writes_enabled? && generation == RepositoryUsage.generation

    key = self.class.key(generation)
    state = REDIS.hgetall(key)
    return if state['finished'] == 'true'

    interval = Integer(ENV.fetch('REPOSITORY_USAGE_BACKFILL_INTERVAL'))
    raise ArgumentError, 'Backfill interval must be non-negative' if interval.negative?

    rows = Repository.transaction do
      Repository.connection.execute("SET LOCAL statement_timeout = '2s'")
      unless state['end_id']
        state['end_id'] = Repository.order(id: :desc).limit(1).pick(:id).to_i.to_s
        REDIS.hset(key, 'end_id', state['end_id'])
      end
      Repository.where('id > ? AND id <= ?', state.fetch('cursor', 0), state['end_id']).order(:id).limit(BATCH_SIZE).pluck(:id, :dependencies_parsed_at)
    end
    if rows.empty?
      REDIS.hset(key, 'finished', 'true')
      return
    end

    rows.each do |id, parsed_at|
      self.class.retry_repository(id) if parsed_at
    end
    REDIS.hset(key, 'cursor', rows.last.first)
    self.class.perform_in(interval, generation)
  end
end
