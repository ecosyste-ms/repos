require 'test_helper'

class RepositoryCommitStatsRefreshTest < ActionDispatch::IntegrationTest
  setup do
    @unique_jobs_enabled = SidekiqUniqueJobs.config.enabled
    SidekiqUniqueJobs.config.enabled = false
    @host = create(:github_host)
    @old_stats = { 'total_commits' => 190, 'total_committers' => 1, 'last_synced_commit' => 'old-sha' }
    @repository = create(:github_repository, host: @host, last_synced_at: 8.days.ago,
      files_changed: false, commit_stats: @old_stats)
    @ping_path = ping_api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)
    [PingWorker, UpdateRepositoryWorker, SyncCommitStatsWorker].each(&:clear)
  end

  teardown do
    [PingWorker, UpdateRepositoryWorker, SyncCommitStatsWorker].each(&:clear)
    SidekiqUniqueJobs.config.enabled = @unique_jobs_enabled
  end

  test 'forced ping refreshes the stored commit summary' do
    stats = {
      'total_commits' => 6049, 'total_committers' => 82, 'mean_commits' => 73.77,
      'dds' => 0.3, 'last_synced_commit' => 'current-sha',
      'last_synced_at' => Time.current.iso8601, 'committers' => [{ 'name' => 'Contributor', 'count' => 10 }]
    }
    request = stub_request(:get, @repository.commits_api_url)
      .to_return(status: 200, body: stats.to_json, headers: { 'Content-Type' => 'application/json' })

    post @ping_path, params: { force: true }
    assert_response :success
    PingWorker.drain
    assert_equal [@repository.id], SyncCommitStatsWorker.jobs.sole['args']
    SyncCommitStatsWorker.drain

    expected = stats.except('last_synced_at', 'committers')
    assert_equal expected, @repository.reload.commit_stats
    get api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_equal expected, response.parsed_body['commit_stats']
    assert_requested request, times: 1
  end

  test 'normal pings do not request commit statistics' do
    post @ping_path
    assert_response :success
    PingWorker.drain

    assert_equal [@repository.id, false], UpdateRepositoryWorker.jobs.sole['args']
    assert_empty SyncCommitStatsWorker.jobs
  end

  test 'unavailable commit statistics preserve the previous summary' do
    stub_request(:get, @repository.commits_api_url).to_return(status: 404)

    post @ping_path, params: { force: true }
    assert_response :success
    PingWorker.drain
    SyncCommitStatsWorker.drain

    assert_equal @old_stats, @repository.reload.commit_stats
  end
end
