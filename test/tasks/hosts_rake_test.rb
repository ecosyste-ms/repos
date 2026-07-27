require "test_helper"
require "rake"

class HostsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("hosts:rotate_gitlab_token")
  end

  teardown do
    ENV.delete('TOKEN')
    ENV.delete('URL')
    ENV.delete('DAYS')
    ENV.delete('HOST')
  end

  test "get_gitlab_token prints the token from redis" do
    host = create(:gitlab_host)
    REDIS.set("gitlab_token:#{host.id}", 'glpat-stored')

    out, _ = capture_io { Rake::Task["hosts:get_gitlab_token"].execute }

    assert_equal "glpat-stored\n", out
  ensure
    REDIS.del("gitlab_token:#{host.id}") if host
  end

  test "set_gitlab_token writes the token to redis" do
    host = create(:gitlab_host)
    ENV['TOKEN'] = 'glpat-fresh'

    capture_io { Rake::Task["hosts:set_gitlab_token"].execute }

    assert_equal 'glpat-fresh', REDIS.get("gitlab_token:#{host.id}")
  ensure
    REDIS.del("gitlab_token:#{host.id}") if host
  end

  test "rotate_gitlab_token posts current token and prints the new one" do
    ENV['TOKEN'] = 'glpat-old'

    stub_request(:post, "https://gitlab.com/api/v4/personal_access_tokens/self/rotate")
      .with(
        headers: { 'Private-Token' => 'glpat-old' },
        body: { expires_at: (Date.today + 90).iso8601 }.to_json
      )
      .to_return(
        status: 200,
        body: { token: 'glpat-new', expires_at: '2099-01-01', scopes: ['read_api'] }.to_json
      )

    out, _ = capture_io { Rake::Task["hosts:rotate_gitlab_token"].execute }

    assert_match 'glpat-new', out
    assert_match '2099-01-01', out
    assert_match 'read_api', out
  end

  test "rotate_gitlab_token honours URL and DAYS" do
    ENV['TOKEN'] = 'glpat-old'
    ENV['URL'] = 'https://gitlab.example.org'
    ENV['DAYS'] = '30'

    stub = stub_request(:post, "https://gitlab.example.org/api/v4/personal_access_tokens/self/rotate")
      .with(body: { expires_at: (Date.today + 30).iso8601 }.to_json)
      .to_return(status: 200, body: { token: 'x', expires_at: 'y', scopes: [] }.to_json)

    capture_io { Rake::Task["hosts:rotate_gitlab_token"].execute }

    assert_requested stub
  end

  test "refresh_gitlab_token rotates the redis token for a named host" do
    host = create(:gitlab_host)
    REDIS.set("gitlab_token:#{host.id}", 'glpat-old')
    ENV['HOST'] = 'GitLab'

    stub_request(:post, "https://gitlab.com/api/v4/personal_access_tokens/self/rotate")
      .with(headers: { 'Private-Token' => 'glpat-old' })
      .to_return(status: 200, body: { token: 'glpat-new', expires_at: '2099-01-01' }.to_json)

    out, _ = capture_io { Rake::Task["hosts:refresh_gitlab_token"].execute }

    assert_equal 'glpat-new', REDIS.get("gitlab_token:#{host.id}")
    assert_match 'glpat-new', out
    assert_match '2099-01-01', out
  ensure
    REDIS.del("gitlab_token:#{host.id}") if host
  end

  test "refresh_gitlab_token without HOST rotates every gitlab host with a token and skips the rest" do
    with_token = create(:gitlab_host, name: 'gitlab.example.org', url: 'https://gitlab.example.org')
    without_token = create(:gitlab_host, name: 'gitlab.other.org', url: 'https://gitlab.other.org')
    create(:github_host)
    REDIS.set("gitlab_token:#{with_token.id}", 'glpat-a')

    stub = stub_request(:post, "https://gitlab.example.org/api/v4/personal_access_tokens/self/rotate")
      .with(headers: { 'Private-Token' => 'glpat-a' })
      .to_return(status: 200, body: { token: 'glpat-b', expires_at: '2099-01-01' }.to_json)

    out, _ = capture_io { Rake::Task["hosts:refresh_gitlab_token"].execute }

    assert_requested stub
    assert_equal 'glpat-b', REDIS.get("gitlab_token:#{with_token.id}")
    assert_match 'gitlab.example.org: new token glpat-b', out
    assert_match 'gitlab.other.org: no token, skipping', out
  ensure
    REDIS.del("gitlab_token:#{with_token.id}") if with_token
  end

  test "refresh_gitlab_token continues past a failing host" do
    bad = create(:gitlab_host, name: 'bad.example.org', url: 'https://bad.example.org')
    good = create(:gitlab_host, name: 'good.example.org', url: 'https://good.example.org')
    REDIS.set("gitlab_token:#{bad.id}", 'glpat-bad')
    REDIS.set("gitlab_token:#{good.id}", 'glpat-good')

    stub_request(:post, "https://bad.example.org/api/v4/personal_access_tokens/self/rotate")
      .to_return(status: 401, body: '{"message":"401 Unauthorized"}')
    stub_request(:post, "https://good.example.org/api/v4/personal_access_tokens/self/rotate")
      .to_return(status: 200, body: { token: 'glpat-good2', expires_at: '2099-01-01' }.to_json)

    _, err = capture_io { Rake::Task["hosts:refresh_gitlab_token"].execute }

    assert_match 'bad.example.org: rotation failed: 401', err
    assert_equal 'glpat-bad', REDIS.get("gitlab_token:#{bad.id}")
    assert_equal 'glpat-good2', REDIS.get("gitlab_token:#{good.id}")
  ensure
    REDIS.del("gitlab_token:#{bad.id}") if bad
    REDIS.del("gitlab_token:#{good.id}") if good
  end

  test "rotate_gitlab_token aborts on non-success" do
    ENV['TOKEN'] = 'glpat-old'

    stub_request(:post, "https://gitlab.com/api/v4/personal_access_tokens/self/rotate")
      .to_return(status: 401, body: '{"message":"401 Unauthorized"}')

    assert_raises(SystemExit) do
      capture_io { Rake::Task["hosts:rotate_gitlab_token"].execute }
    end
  end
end
