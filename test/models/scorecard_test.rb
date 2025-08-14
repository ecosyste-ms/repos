require "test_helper"

class ScorecardTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository)
  end

  context 'lookup method' do
    should 'create scorecard for repository' do
      host = create(:host)
      repository = create(:repository, host: host)
      
      stub_request(:get, "https://api.scorecard.dev/projects/#{repository.html_url.gsub(%r{http(s)?://}, '')}")
        .to_return(status: 200, body: { score: 7.5, repo: { name: repository.full_name } }.to_json)
      
      scorecard = Scorecard.lookup(repository)
      
      assert scorecard.persisted?
      assert_equal repository, scorecard.repository
      assert_equal 7.5, scorecard.score
    end

    should 'return existing scorecard for repository' do
      host = create(:host)
      repository = create(:repository, host: host)
      existing_scorecard = create(:scorecard, repository: repository)
      
      scorecard = Scorecard.lookup(repository)
      
      assert_equal existing_scorecard.id, scorecard.id
      assert_equal repository, scorecard.repository
    end

    should 'return nil for blank repository' do
      scorecard = Scorecard.lookup('')
      assert_nil scorecard
      
      scorecard = Scorecard.lookup(nil)
      assert_nil scorecard
    end

    should 'return nil when API returns 404' do
      host = create(:host)
      repository = create(:repository, host: host)
      
      stub_request(:get, "https://api.scorecard.dev/projects/#{repository.html_url.gsub(%r{http(s)?://}, '')}")
        .to_return(status: 404)
      
      scorecard = Scorecard.lookup(repository)
      
      assert_nil scorecard
    end
  end

  context 'url method' do
    should 'return repository html_url' do
      host = create(:host)
      repository = create(:repository, host: host, full_name: 'rails/rails')
      scorecard = create(:scorecard, repository: repository)
      
      assert_equal repository.html_url, scorecard.url
    end
  end

  context 'repository_name method' do
    should 'return repository name from data' do
      scorecard = Scorecard.new(data: { 'repo' => { 'name' => 'rails/rails' } })
      assert_equal 'rails/rails', scorecard.repository_name
    end
  end

  context 'html_url method' do
    should 'return scorecard viewer url' do
      scorecard = Scorecard.new(data: { 'repo' => { 'name' => 'rails/rails' } })
      assert_equal 'https://scorecard.dev/viewer/?uri=rails/rails', scorecard.html_url
    end
  end
end