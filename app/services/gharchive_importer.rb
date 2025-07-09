class GharchiveImporter
  GHARCHIVE_BASE_URL = 'https://data.gharchive.org'
  
  attr_reader :import_stats
  
  def initialize(host = nil)
    @host = host || Host.find_or_create_by(name: 'GitHub')
    @import_stats = { repositories_processed: 0, repositories_with_releases: 0 }
  end

  def import_hour(date, hour, update_counts: true, test_mode: false, skip_if_imported: true)
    Rails.logger.info "[GHArchive] Starting import for #{date} hour #{hour}"
    
    # Check if already imported
    if skip_if_imported && Import.already_imported?(date, hour)
      Rails.logger.info "[GHArchive] Skipping #{date} hour #{hour} - already imported"
      return true
    end
    
    # Reset stats for this import
    @import_stats = { repositories_processed: 0, repositories_with_releases: 0 }
    
    url = build_url(date, hour)
    compressed_data = download_file(url)
    if compressed_data.nil?
      Import.record_failure(date, hour, "Failed to download file from #{url}")
      return false
    end
    
    events = parse_jsonl(compressed_data, limit: test_mode ? 100 : nil)
    process_events(events)
    
    # Record successful import
    Import.create_from_import(date, hour, @import_stats)
    Rails.logger.info "[GHArchive] Import completed for #{date} hour #{hour}: #{@import_stats}"
    
    true
  rescue => e
    Rails.logger.error "[GHArchive] Import failed for #{date} hour #{hour}: #{e.message}"
    Import.record_failure(date, hour, e.message)
    false
  end

  def import_date_range(start_date, end_date)
    (start_date..end_date).each do |date|
      24.times do |hour|
        import_hour(date, hour)
      end
    end
  end

  private

  def build_url(date, hour)
    formatted_date = date.strftime('%Y-%m-%d')
    "#{GHARCHIVE_BASE_URL}/#{formatted_date}-#{hour}.json.gz"
  end

  def download_file(url)
    Rails.logger.info "[GHArchive] Downloading #{url}"
    
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    
    if response.code == '200'
      response.body
    else
      Rails.logger.error "[GHArchive] Failed to download #{url}: #{response.code}"
      nil
    end
  rescue => e
    Rails.logger.error "[GHArchive] Download error for #{url}: #{e.message}"
    nil
  end

  def parse_jsonl(compressed_data, limit: nil)
    events = []
    count = 0
    
    Zlib::GzipReader.new(StringIO.new(compressed_data)).each_line do |line|
      event = JSON.parse(line)
      
      # Only process events that affect repositories
      if event['type'].in?(%w[PushEvent ReleaseEvent])
        events << event
        count += 1
        break if limit && count >= limit
      end
    rescue JSON::ParserError => e
      Rails.logger.warn "[GHArchive] Skipping malformed JSON: #{e.message}"
    end
    
    Rails.logger.info "[GHArchive] Parsed #{events.size} relevant events"
    events
  end

  def process_events(events)
    # Group events by repository
    repos_by_name = events.group_by { |e| e['repo']['name'] }
    repos_with_releases = Set.new
    
    # Find repositories with release events
    events.each do |event|
      if event['type'] == 'ReleaseEvent'
        repos_with_releases << event['repo']['name']
      end
    end
    
    Rails.logger.info "[GHArchive] Processing #{repos_by_name.size} repositories, #{repos_with_releases.size} with releases"
    
    # Process each unique repository
    repos_by_name.each do |repo_name, repo_events|
      process_repository(repo_name, repos_with_releases.include?(repo_name))
    end
    
    @import_stats[:repositories_processed] = repos_by_name.size
    @import_stats[:repositories_with_releases] = repos_with_releases.size
  end

  def process_repository(repo_name, has_releases)
    # Find existing repository
    repository = Repository.find_by(host: @host, full_name: repo_name)
    
    if repository
      Rails.logger.info "[GHArchive] Processing #{repo_name}#{has_releases ? ' (with releases)' : ''}"
      
      # Queue PingWorker for this repository
      PingWorker.perform_async("GitHub", repository.full_name)
      
      # Queue download_tags_async if repository had release events
      if has_releases
        repository.download_tags_async
      end
    else
      Rails.logger.debug "[GHArchive] Repository #{repo_name} not found, skipping"
    end
  end

end