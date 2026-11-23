require 'test_helper'

class GharchiveImporterTest < ActiveSupport::TestCase
  setup do
    @host = create(:github_host)
    DownloadTagsWorker.jobs.clear
    PingWorker.jobs.clear
  end

  test 'downloads tags for a repository with a release event' do
    repository = create(:repository, host: @host, full_name: 'owner/repo')
    stub_archive([{ type: 'ReleaseEvent', repo: { name: 'owner/repo' } }])

    assert GharchiveImporter.new(@host).import_hour(Date.new(2026, 11, 1), 3)

    assert_equal [[repository.id]], DownloadTagsWorker.jobs.map { |job| job['args'] }
    assert_equal [['GitHub', 'owner/repo']], PingWorker.jobs.map { |job| job['args'] }
  end

  test 'does not download tags for a repository that only used the name previously' do
    repository = create(:repository, host: @host, full_name: 'owner/reused')
    repository.update!(full_name: 'owner/renamed')
    stub_archive([{ type: 'ReleaseEvent', repo: { name: 'owner/reused' } }])

    assert GharchiveImporter.new(@host).import_hour(Date.new(2026, 11, 1), 3)

    assert_empty DownloadTagsWorker.jobs
    assert_equal [['GitHub', 'owner/reused']], PingWorker.jobs.map { |job| job['args'] }
  end

  def stub_archive(events)
    body = ActiveSupport::Gzip.compress(events.map(&:to_json).join("\n"))
    stub_request(:get, 'https://data.gharchive.org/2026-11-01-3.json.gz').to_return(status: 200, body: body)
  end
end
