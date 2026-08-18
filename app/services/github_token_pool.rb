require "digest"

class GithubRateLimitUnavailable < StandardError
  attr_reader :retry_after

  def initialize(retry_after)
    @retry_after = retry_after
    super("All GitHub tokens are inside the rate limit buffer; retry in #{retry_after} seconds")
  end
end

class GithubTokenPool
  DEFAULT_BUFFER = 100
  DEFAULT_SECONDARY_PAUSE = 60
  GLOBAL_PAUSE_KEY = "github_rate_limit:secondary"

  def initialize(redis: REDIS, buffer: ENV.fetch("GITHUB_RATE_LIMIT_BUFFER", DEFAULT_BUFFER).to_i, now: -> { Time.now.to_i })
    @redis = redis
    @buffer = buffer
    @now = now
  end

  def fetch(tokens)
    return if tokens.empty?

    raise GithubRateLimitUnavailable.new(global_retry_after) if @redis.exists?(GLOBAL_PAUSE_KEY)

    keys = tokens.map { |token| token_pause_key(token) }
    available_tokens = tokens.zip(@redis.mget(*keys)).filter_map do |token, paused|
      token unless paused
    end
    return available_tokens.sample if available_tokens.any?

    retry_after = keys.filter_map { |key| positive_ttl(key) }.min || DEFAULT_SECONDARY_PAUSE
    raise GithubRateLimitUnavailable.new(retry_after)
  end

  def record_response(request_headers:, response_headers:, status:, body:)
    token = access_token(request_headers)
    return unless token

    if secondary_limit?(status, body)
      pause_globally(retry_after(response_headers))
      return
    end

    remaining = header(response_headers, "x-ratelimit-remaining")
    return unless remaining && remaining.to_i <= @buffer

    reset_at = header(response_headers, "x-ratelimit-reset").to_i
    pause_token(token, [reset_at - @now.call, 1].max)
  end

  def token_pause_key(token)
    "github_rate_limit:token:#{Digest::SHA256.hexdigest(token)}"
  end

  def pause_token(token, seconds)
    @redis.set(token_pause_key(token), "1", ex: seconds)
  end

  def pause_globally(seconds)
    @redis.set(GLOBAL_PAUSE_KEY, "1", ex: seconds)
  end

  def access_token(headers)
    authorization = header(headers, "authorization").to_s
    authorization.sub(/\A(?:Bearer|token)\s+/i, "").presence
  end

  def secondary_limit?(status, body)
    [403, 429].include?(status.to_i) && body.to_s.match?(/secondary rate limit/i)
  end

  def retry_after(headers)
    value = header(headers, "retry-after").to_i
    value.positive? ? value : DEFAULT_SECONDARY_PAUSE
  end

  def header(headers, name)
    headers[name] || headers[name.downcase] || headers[name.split("-").map(&:capitalize).join("-")]
  end

  def global_retry_after
    positive_ttl(GLOBAL_PAUSE_KEY) || DEFAULT_SECONDARY_PAUSE
  end

  def positive_ttl(key)
    ttl = @redis.ttl(key)
    ttl if ttl.positive?
  end
end

class GithubRateLimitMiddleware < Faraday::Middleware
  def initialize(app, pool: GithubTokenPool.new)
    super(app)
    @pool = pool
  end

  def on_complete(env)
    @pool.record_response(
      request_headers: env.request_headers,
      response_headers: env.response_headers,
      status: env.status,
      body: env.body
    )
  end
end
