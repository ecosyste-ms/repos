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

  context 'risk level methods' do
    setup do
      @scorecard = create(:scorecard)
    end

    should 'return correct risk level for check' do
      assert_equal 'High', @scorecard.risk_level_for_check('Maintained')
      assert_equal 'High', @scorecard.risk_level_for_check('Code-Review')
      assert_equal 'Critical', @scorecard.risk_level_for_check('Dangerous-Workflow')
      assert_equal 'Medium', @scorecard.risk_level_for_check('Packaging')
      assert_equal 'Unknown', @scorecard.risk_level_for_check('NonExistent')
    end

    should 'return correct risk summary counts' do
      summary = @scorecard.risk_summary
      
      assert_equal 1, summary[:critical]  # Dangerous-Workflow
      assert_equal 3, summary[:high]      # Maintained, Code-Review, Branch-Protection
      assert_equal 1, summary[:medium]    # Packaging
      assert_equal 0, summary[:low]       # none in our test data
      assert_equal 1, summary[:not_applicable]  # Packaging has score -1
    end

    should 'return correct badge info for checks' do
      maintained_check = @scorecard.checks.find { |c| c['name'] == 'Maintained' }
      badge = @scorecard.risk_level_badge_for_check(maintained_check)
      assert_equal 'High Risk', badge[:text]
      assert_equal 'bg-danger', badge[:class]

      dangerous_check = @scorecard.checks.find { |c| c['name'] == 'Dangerous-Workflow' }
      badge = @scorecard.risk_level_badge_for_check(dangerous_check)
      assert_equal 'Critical Risk', badge[:text]
      assert_equal 'bg-dark', badge[:class]

      packaging_check = @scorecard.checks.find { |c| c['name'] == 'Packaging' }
      badge = @scorecard.risk_level_badge_for_check(packaging_check)
      assert_equal 'Not Applicable', badge[:text]
      assert_equal 'bg-secondary', badge[:class]
    end

    should 'have frozen risk levels hash' do
      risk_levels = Scorecard.risk_levels
      assert risk_levels.frozen?
      assert_equal 'Critical', risk_levels['Dangerous-Workflow']
      assert_equal 'High', risk_levels['Maintained']
    end
  end
end