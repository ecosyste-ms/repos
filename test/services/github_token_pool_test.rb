require "test_helper"

class GithubTokenPoolTest < ActiveSupport::TestCase
  setup do
    @redis = mock("redis")
    @pool = GithubTokenPool.new(redis: @redis, buffer: 100, now: -> { 1_000 })
  end

  def headers(hash)
    Faraday::Utils::Headers.new(hash)
  end

  test "returns nil when there are no tokens" do
    assert_nil @pool.fetch([])
  end

  test "selects from tokens that are not paused" do
    tokens = ["paused-token", "available-token"]
    keys = tokens.map { |token| @pool.token_pause_key(token) }
    @redis.expects(:exists?).with(GithubTokenPool::GLOBAL_PAUSE_KEY).returns(false)
    @redis.expects(:mget).with(*keys).returns(["1", nil])

    assert_equal "available-token", @pool.fetch(tokens)
  end

  test "raises with the shortest retry time when every token is paused" do
    tokens = ["first-token", "second-token"]
    keys = tokens.map { |token| @pool.token_pause_key(token) }
    @redis.expects(:exists?).with(GithubTokenPool::GLOBAL_PAUSE_KEY).returns(false)
    @redis.expects(:mget).with(*keys).returns(["1", "1"])
    @redis.expects(:ttl).with(keys.first).returns(45)
    @redis.expects(:ttl).with(keys.second).returns(20)

    error = assert_raises(GithubRateLimitUnavailable) { @pool.fetch(tokens) }

    assert_equal 20, error.retry_after
  end

  test "raises while the whole pool is paused" do
    @redis.expects(:exists?).with(GithubTokenPool::GLOBAL_PAUSE_KEY).returns(true)
    @redis.expects(:ttl).with(GithubTokenPool::GLOBAL_PAUSE_KEY).returns(30)

    error = assert_raises(GithubRateLimitUnavailable) { @pool.fetch(["token"]) }

    assert_equal 30, error.retry_after
  end

  test "pauses a token when its remaining quota reaches the buffer" do
    key = @pool.token_pause_key("token")
    @redis.expects(:set).with(key, "1", ex: 200)

    @pool.record_response(
      request_headers: headers("Authorization" => "token token"),
      response_headers: headers("X-RateLimit-Limit" => "5000", "X-RateLimit-Remaining" => "100", "X-RateLimit-Reset" => "1200"),
      status: 200,
      body: ""
    )
  end

  test "leaves a token available while its remaining quota is above the buffer" do
    @redis.expects(:set).never

    @pool.record_response(
      request_headers: headers("Authorization" => "token token"),
      response_headers: headers("X-RateLimit-Limit" => "5000", "X-RateLimit-Remaining" => "101", "X-RateLimit-Reset" => "1200"),
      status: 200,
      body: ""
    )
  end

  test "ignores rate limit resources whose limit is below the buffer" do
    @redis.expects(:set).never

    @pool.record_response(
      request_headers: headers("Authorization" => "token token"),
      response_headers: headers("X-RateLimit-Limit" => "30", "X-RateLimit-Remaining" => "29", "X-RateLimit-Reset" => "1200"),
      status: 200,
      body: ""
    )
  end

  test "pauses the whole pool for a secondary limit response" do
    @redis.expects(:set).with(GithubTokenPool::GLOBAL_PAUSE_KEY, "1", ex: 90)

    @pool.record_response(
      request_headers: headers("Authorization" => "Bearer token"),
      response_headers: headers("Retry-After" => "90", "X-RateLimit-Remaining" => "4000"),
      status: 429,
      body: '{"message":"You have exceeded a secondary rate limit."}'
    )
  end

  test "uses a one minute pause when a secondary limit has no retry header" do
    @redis.expects(:set).with(GithubTokenPool::GLOBAL_PAUSE_KEY, "1", ex: 60)

    @pool.record_response(
      request_headers: headers("Authorization" => "token token"),
      response_headers: headers({}),
      status: 403,
      body: '{"message":"You have exceeded a secondary rate limit."}'
    )
  end

  test "middleware records completed responses" do
    pool = mock("pool")
    middleware = GithubRateLimitMiddleware.new(mock("app"), pool: pool)
    env = OpenStruct.new(
      request_headers: {"Authorization" => "token token"},
      response_headers: {"x-ratelimit-remaining" => "99"},
      status: 200,
      body: "{}"
    )
    pool.expects(:record_response).with(
      request_headers: env.request_headers,
      response_headers: env.response_headers,
      status: env.status,
      body: env.body
    )

    middleware.on_complete(env)
  end
end
