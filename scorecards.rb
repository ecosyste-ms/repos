require 'open-uri'
require 'csv'

# Temporary method to fetch and create scorecard from URL
def fetch_and_create_from_url(url)
  return nil if url.blank?
  
  url_without_protocol = url.gsub(%r{http(s)?://}, '')
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
  Scorecard.create(data: json, last_synced_at: Time.now)
rescue
  nil
end

# Fetch and parse the CSV
csv_url = 'https://raw.githubusercontent.com/ossf/scorecard/refs/heads/main/cron/internal/data/projects.csv'
csv_data = URI.open(csv_url).read
repos = CSV.parse(csv_data, headers: true)

puts "Found #{repos.count} repositories to process"

# Preload all existing scorecard repo names into a Set for fast lookup
puts "Loading existing scorecard repo names into memory..."
existing_repo_names = Set.new
Scorecard.find_each do |scorecard|
  repo_name = scorecard.data&.dig('repo', 'name')
  existing_repo_names.add(repo_name.downcase) if repo_name
end
puts "Loaded #{existing_repo_names.size} existing scorecard repo names"

processed = 0
created = 0

repos.each_with_index do |row, index|
  repo_url = row['repo']
  
  # Check if scorecard already exists for this repo using Set lookup (O(1) instead of database query)
  if existing_repo_names.include?(repo_url.downcase)
    print '.'
  else
    puts "Creating scorecard record for #{repo_url} (#{index + 1}/#{repos.count})"
    
    # Fetch and create scorecard with actual data from API
    scorecard = fetch_and_create_from_url(repo_url)
    
    if scorecard
      created += 1
      existing_repo_names.add(repo_url)  # Add to set to avoid duplicates in this run
    else
      puts "  Failed to fetch scorecard data for #{repo_url}"
    end

    processed += 1

    # Progress update every 100 repos
    if processed % 100 == 0
      puts "Progress: #{processed}/#{repos.count} processed, #{created} created"
    end
  end
end

puts "Completed! Processed #{processed} repos, created #{created} scorecard records"
