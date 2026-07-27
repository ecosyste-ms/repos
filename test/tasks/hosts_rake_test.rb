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

  test "refresh_gitlab_token rotates the redis token in place" do
    host = create(:gitlab_host)
    REDIS.set("gitlab_token:#{host.id}", 'glpat-old')

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

  test "refresh_gitlab_token leaves redis untouched on failure" do
    host = create(:gitlab_host)
    REDIS.set("gitlab_token:#{host.id}", 'glpat-old')

    stub_request(:post, "https://gitlab.com/api/v4/personal_access_tokens/self/rotate")
      .to_return(status: 401, body: '{"message":"401 Unauthorized"}')

    assert_raises(SystemExit) do
      capture_io { Rake::Task["hosts:refresh_gitlab_token"].execute }
    end

    assert_equal 'glpat-old', REDIS.get("gitlab_token:#{host.id}")
  ensure
    REDIS.del("gitlab_token:#{host.id}") if host
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
