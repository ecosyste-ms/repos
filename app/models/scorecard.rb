class Scorecard < ApplicationRecord
  belongs_to :repository

  def self.sync_least_recently_synced
    Scorecard.where(last_synced_at: nil).each(&:fetch_scorecard_async)
    Scorecard.where('last_synced_at < ?', 1.day.ago).each(&:fetch_scorecard_async)
  end

  def self.lookup(repository)
    return nil if repository.blank?
    scorecard = find_by(repository: repository)
    return scorecard if scorecard
    
    fetch_and_create(repository)
  end

  def self.fetch_and_create(repository)
    return nil if repository.blank?
    
    url_without_protocol = repository.html_url.gsub(%r{http(s)?://}, '')
    scorecard_url = "https://api.scorecard.dev/projects/#{url_without_protocol}"

    connection = Faraday.new do |builder|
      builder.use Faraday::FollowRedirects::Middleware
      builder.request :instrumentation
      builder.request :retry, max: 3, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2
      builder.adapter Faraday.default_adapter
    end

    response = connection.get(scorecard_url)
    return nil unless response.success?
      
    json = JSON.parse(response.body)
    create(repository: repository, data: json, last_synced_at: Time.now)
  rescue
    nil
  end

  def url
    repository.html_url
  end

  def fetch
    updated_scorecard = self.class.fetch_and_update(repository)
    return updated_scorecard if updated_scorecard
    
    update(last_synced_at: Time.now)
    nil
  end

  def self.fetch_and_update(repository)
    return nil if repository.blank?
    
    url_without_protocol = repository.html_url.gsub(%r{http(s)?://}, '')
    scorecard_url = "https://api.scorecard.dev/projects/#{url_without_protocol}"

    connection = Faraday.new do |builder|
      builder.use Faraday::FollowRedirects::Middleware
      builder.request :instrumentation
      builder.request :retry, max: 3, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2
      builder.adapter Faraday.default_adapter
    end

    response = connection.get(scorecard_url)
    return nil unless response.success?
      
    json = JSON.parse(response.body)
    scorecard = find_by(repository: repository)
    scorecard&.update(data: json, last_synced_at: Time.now)
    scorecard
  rescue
    nil
  end

  def fetch_scorecard_async
    FetchScorecardWorker.perform_async(id)
  end

  def repository_name
    data['repo']['name']
  end

  def score
    data['score']
  end

  def commit
    data['repo']['commit']
  end

  def generated_at
    data['date']
  end

  def scorecard_version
    data['scorecard']['version']
  end

  def checks
    data['checks']
  end

  def html_url
    "https://scorecard.dev/viewer/?uri=#{repository_name}"
  end

  def self.risk_levels
    {
      'Binary-Artifacts' => 'High',
      'Branch-Protection' => 'High',
      'CI-Tests' => 'Low',
      'CII-Best-Practices' => 'Low',
      'Code-Review' => 'High',
      'Contributors' => 'Low',
      'Dangerous-Workflow' => 'Critical',
      'Dependency-Update-Tool' => 'High',
      'Fuzzing' => 'Medium',
      'License' => 'Low',
      'Maintained' => 'High',
      'Packaging' => 'Medium',
      'Pinned-Dependencies' => 'Medium',
      'SAST' => 'Medium',
      'SBOM' => 'Medium',
      'Security-Policy' => 'Medium',
      'Signed-Releases' => 'High',
      'Token-Permissions' => 'High',
      'Vulnerabilities' => 'High'
    }.freeze
  end

  def risk_level_for_check(check_name)
    self.class.risk_levels[check_name] || 'Unknown'
  end

  def risk_summary
    return {} unless checks.present?

    {
      critical: checks.count { |c| risk_level_for_check(c['name']) == 'Critical' },
      high: checks.count { |c| risk_level_for_check(c['name']) == 'High' },
      medium: checks.count { |c| risk_level_for_check(c['name']) == 'Medium' },
      low: checks.count { |c| risk_level_for_check(c['name']) == 'Low' },
      not_applicable: checks.count { |c| c['score'] == -1 }
    }
  end

  def risk_level_badge_for_check(check)
    risk_level = risk_level_for_check(check['name'])
    
    return { text: 'Not Applicable', class: 'bg-secondary' } if check['score'] == -1
    
    case risk_level
    when 'Critical'
      { text: 'Critical Risk', class: 'bg-dark' }
    when 'High'
      { text: 'High Risk', class: 'bg-danger' }
    when 'Medium'
      { text: 'Medium Risk', class: 'bg-warning' }
    when 'Low'
      { text: 'Low Risk', class: 'bg-success' }
    else
      { text: 'Unknown Risk', class: 'bg-secondary' }
    end
  end
end