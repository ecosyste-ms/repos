require 'test_helper'

class RepositoryRefreshTest < ActionDispatch::IntegrationTest
  setup do
    @unique_jobs_enabled = SidekiqUniqueJobs.config.enabled
    SidekiqUniqueJobs.config.enabled = false
    @host = create(:github_host)
    @repository = create(:github_repository, host: @host, uuid: '123',
      updated_at: 3.months.ago, pushed_at: 2.months.ago, last_synced_at: 4.days.ago)
    @path = api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)
    @ping_path = ping_api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)
    [PingWorker, UpdateRepositoryWorker, SyncExtraDetailsWorker, PingPackagesWorker].each(&:clear)
  end

  teardown do
    [PingWorker, UpdateRepositoryWorker, SyncExtraDetailsWorker, PingPackagesWorker].each(&:clear)
    SidekiqUniqueJobs.config.enabled = @unique_jobs_enabled
  end

  test 'get and post pings are not cached and enqueue each request' do
    get @ping_path
    assert_response :success
    assert_refresh_not_cached
    post @ping_path, params: { force: true }
    assert_response :success
    assert_refresh_not_cached

    assert_equal [[@host.name, @repository.full_name, false],
                  [@host.name, @repository.full_name, true]], PingWorker.jobs.map { |job| job['args'] }
  end

  test 'conditional get ping still returns an acknowledgement' do
    get @ping_path
    get @ping_path, headers: { 'If-None-Match' => response.headers['ETag'] }
    assert_response :success
    assert_refresh_not_cached
    assert_equal 2, PingWorker.jobs.size
  end

  test 'post ping accepts host aliases without losing the forced refresh' do
    post ping_api_v1_host_repository_path(host_id: 'github.com', id: @repository.full_name),
      params: { force: true }

    assert_response :success
    assert_nil response.headers['Location']
    assert_refresh_not_cached
    assert_equal [@host.name, @repository.full_name, true], PingWorker.jobs.sole['args']
    PingWorker.drain
    assert_equal [@repository.id, true], UpdateRepositoryWorker.jobs.sole['args']
    assert_nil UpdateRepositoryWorker.jobs.sole['at']
  end

  test 'unique jobs deduplicate scheduled updates without blocking forced pings' do
    SidekiqUniqueJobs.config.enabled = true
    middleware = SidekiqUniqueJobs::Middleware::Server
    chain = Sidekiq::Testing.server_middleware
    middleware_present = chain.exists?(middleware)
    chain.add(middleware) unless middleware_present
    prefix = "repository-refresh-test:#{SecureRandom.uuid}"
    @repository.update!(files_changed: false)

    PingWorker.use_options(lock_prefix: prefix) do
      UpdateRepositoryWorker.use_options(lock_prefix: prefix) do
        2.times do
          post @ping_path
          assert_response :success
          assert_equal 1, PingWorker.jobs.size
          PingWorker.drain
        end

        scheduled = UpdateRepositoryWorker.jobs.sole
        assert_equal [@repository.id, false], scheduled['args']
        assert_in_delta @repository.next_sync_at.to_f, scheduled['at'], 0.001

        post @ping_path, params: { force: true }
        assert_response :success
        PingWorker.drain

        assert_equal 2, UpdateRepositoryWorker.jobs.size
        forced = UpdateRepositoryWorker.jobs.find { |job| job['args'] == [@repository.id, true] }
        assert_not_nil forced
        assert_nil forced['at']
        refute_equal scheduled['lock_digest'], forced['lock_digest']
      end
    end
  ensure
    chain.remove(middleware) if chain && !middleware_present
  end

  test 'normal ping schedules the update at the weekly deadline' do
    travel_to Time.current.change(usec: 0) do
      @repository.update!(last_synced_at: 4.days.ago)
      @repository.update!(files_changed: true)
      post @ping_path
      PingWorker.drain

      job = UpdateRepositoryWorker.jobs.sole
      assert_equal [@repository.id, false], job['args']
      assert_equal 3.days.from_now.to_f, job['at']
      assert_empty SyncExtraDetailsWorker.jobs
    end
  end

  test 'due ping queues an immediate update' do
    @repository.update!(last_synced_at: 8.days.ago)
    post @ping_path
    PingWorker.drain

    job = UpdateRepositoryWorker.jobs.sole
    assert_equal [@repository.id, false], job['args']
    assert_nil job['at']
  end

  test 'forced ping updates metadata and invalidates the previous etag' do
    get @path
    etag = response.headers['ETag']
    old_updated_at = @repository.updated_at
    pushed_at = 1.hour.ago.change(usec: 0)
    Hosts::Github.any_instance.stubs(:fetch_random_token).returns(nil)
    stub_request(:get, 'https://api.github.com/repositories/123').to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: {
        id: 123, full_name: @repository.full_name, owner: { login: @repository.owner },
        description: 'Updated upstream', created_at: @repository.created_at.iso8601,
        updated_at: old_updated_at.iso8601(6), pushed_at: pushed_at.iso8601
      }.to_json
    )

    post @ping_path, params: { force: true }
    PingWorker.drain
    assert_nil UpdateRepositoryWorker.jobs.sole['at']
    UpdateRepositoryWorker.drain

    @repository.reload
    assert_equal pushed_at, @repository.pushed_at
    assert_equal old_updated_at, @repository.updated_at
    get @path, headers: { 'If-None-Match' => etag }
    assert_response :success
    assert_equal pushed_at, Time.iso8601(response.parsed_body['pushed_at'])
    refute_equal etag, response.headers['ETag']
    assert_nil response.headers['Last-Modified']
  end

  test 'unchanged representation returns not modified' do
    get @path
    get @path, headers: { 'If-None-Match' => response.headers['ETag'] }
    assert_response :not_modified
  end

  test 'github modification dates cannot validate the representation' do
    get @path, headers: { 'If-Modified-Since' => @repository.updated_at.httpdate }
    assert_response :success
    assert_nil response.headers['Last-Modified']
  end

  test 'lookup invalidates its etag when commit stats change without timestamps' do
    lookup_path = api_v1_repositories_lookup_path(url: @repository.html_url)
    get lookup_path
    etag = response.headers['ETag']
    @repository.update!(commit_stats: { total_commits: 6000 })
    get lookup_path, headers: { 'If-None-Match' => etag }

    assert_response :success
    assert_equal 6000, response.parsed_body.dig('commit_stats', 'total_commits')
    refute_equal etag, response.headers['ETag']
  end

  test 'forced lookup ignores conditional headers and cannot be cached' do
    lookup_path = api_v1_repositories_lookup_path(url: @repository.html_url)
    get lookup_path
    etag = response.headers['ETag']
    UpdateRepositoryWorker.clear
    get lookup_path, params: { force: true }, headers: { 'If-None-Match' => etag }

    assert_response :success
    assert_refresh_not_cached
    assert_equal [@repository.id, true], UpdateRepositoryWorker.jobs.sole['args']
    assert_nil UpdateRepositoryWorker.jobs.sole['at']
  end

  test 'false force parameter keeps the normal schedule' do
    post @ping_path, params: { force: 'false' }
    PingWorker.drain
    assert UpdateRepositoryWorker.jobs.sole['at'] > Time.current.to_f
  end

  test 'cache busting lookup is not stored and keeps the normal sync schedule' do
    get api_v1_repositories_lookup_path(url: @repository.html_url, _refresh: 'unique-request')

    assert_response :success
    assert_refresh_not_cached
    assert_equal [@repository.id, false], UpdateRepositoryWorker.jobs.sole['args']
    assert UpdateRepositoryWorker.jobs.sole['at'] > Time.current.to_f
  end

  test 'a scheduled update skips a repository that has since been refreshed' do
    post @ping_path
    PingWorker.drain
    @repository.update!(last_synced_at: Time.current)
    Hosts::Github.any_instance.expects(:fetch_repository).never

    UpdateRepositoryWorker.drain
    assert_empty UpdateRepositoryWorker.jobs
  end

  def assert_refresh_not_cached
    %w[Cache-Control CDN-Cache-Control Cloudflare-CDN-Cache-Control].each do |header|
      assert_equal 'no-store', response.headers[header]
    end
  end
end
