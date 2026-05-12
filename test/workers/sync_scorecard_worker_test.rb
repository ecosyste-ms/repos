require 'test_helper'

class SyncScorecardWorkerTest < ActiveSupport::TestCase
  context '#perform' do
    should 'call sync_scorecard on repository' do
      ENV['SCORECARD_SYNC_ENABLED'] = 'true'
      host = create(:host)
      repository = create(:repository, host: host)

      stub_request(:get, "https://api.scorecard.dev/projects/#{repository.html_url.gsub(%r{http(s)?://}, '')}")
        .to_return(status: 200, body: { score: 9.0, repo: { name: repository.full_name } }.to_json)

      worker = SyncScorecardWorker.new
      worker.perform(repository.id)

      repository.reload
      assert_not_nil repository.scorecard
      assert_equal 9.0, repository.scorecard.score
    ensure
      ENV.delete('SCORECARD_SYNC_ENABLED')
    end

    should 'handle non-existent repository gracefully' do
      worker = SyncScorecardWorker.new

      assert_nothing_raised do
        worker.perform(999999)
      end
    end

    should 'not hit api when SCORECARD_SYNC_ENABLED is not set' do
      ENV.delete('SCORECARD_SYNC_ENABLED')
      host = create(:host)
      repository = create(:repository, host: host)

      worker = SyncScorecardWorker.new
      worker.perform(repository.id)

      repository.reload
      assert_nil repository.scorecard
    end
  end
end