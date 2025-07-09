namespace :gharchive do
  desc "Import recent push and release events from GHArchive"
  task import_recent: :environment do
    Rails.logger = Logger.new(STDOUT)
    
    importer = GharchiveImporter.new
    now = Time.current.utc
    
    # Import last 24 hours with a 2-hour delay for data availability
    end_time = now - 2.hours
    start_time = end_time - 24.hours
    
    puts "Importing from #{start_time} to #{end_time}"
    
    (start_time.to_date..end_time.to_date).each do |date|
      start_hour = date == start_time.to_date ? start_time.hour : 0
      end_hour = date == end_time.to_date ? end_time.hour : 23
      
      (start_hour..end_hour).each do |hour|
        timestamp = date.to_time + hour.hours
        next if timestamp < start_time || timestamp > end_time
        
        puts "Importing #{date} hour #{hour}..."
        success = importer.import_hour(date, hour)
        puts success ? "✓ Success" : "✗ Failed"
      end
    end
  end
  
  desc "Import a specific hour from GHArchive"
  task :import_hour, [:date, :hour] => :environment do |t, args|
    date = Date.parse(args[:date])
    hour = args[:hour].to_i
    
    Rails.logger = Logger.new(STDOUT)
    importer = GharchiveImporter.new
    
    puts "Importing #{date} hour #{hour}..."
    success = importer.import_hour(date, hour, skip_if_imported: false)
    puts success ? "✓ Success" : "✗ Failed"
  end
  
  desc "Import a full day from GHArchive"
  task :import_day, [:date] => :environment do |t, args|
    date = Date.parse(args[:date])
    
    Rails.logger = Logger.new(STDOUT)
    importer = GharchiveImporter.new
    
    puts "Importing all 24 hours for #{date}..."
    24.times do |hour|
      puts "Hour #{hour}..."
      success = importer.import_hour(date, hour)
      puts success ? "✓ Success" : "✗ Failed"
    end
  end
  
  desc "Import a date range from GHArchive"
  task :import_range, [:start_date, :end_date] => :environment do |t, args|
    start_date = Date.parse(args[:start_date])
    end_date = Date.parse(args[:end_date])
    
    Rails.logger = Logger.new(STDOUT)
    importer = GharchiveImporter.new
    
    puts "Importing from #{start_date} to #{end_date}..."
    importer.import_date_range(start_date, end_date)
  end
  
  desc "Test GHArchive connection and parsing"
  task test: :environment do
    Rails.logger = Logger.new(STDOUT)
    
    importer = GharchiveImporter.new
    now = Time.current.utc
    
    # Test with the hour from 3 hours ago
    target_time = now - 3.hours
    date = target_time.to_date
    hour = target_time.hour
    
    puts "Testing with #{date} hour #{hour}..."
    success = importer.import_hour(date, hour, test_mode: true, skip_if_imported: false)
    
    if success
      puts "✓ Test successful!"
      puts "Stats: #{importer.import_stats}"
    else
      puts "✗ Test failed!"
    end
  end
  
  desc "Analyze GHArchive event structures"
  task analyze_events: :environment do
    require 'net/http'
    require 'json'
    require 'zlib'
    require 'stringio'
    
    # Use a known recent date
    date = Date.new(2025, 1, 9)
    hour = 12
    
    url = "https://data.gharchive.org/#{date.strftime('%Y-%m-%d')}-#{hour}.json.gz"
    
    puts "Downloading #{url}..."
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    
    if response.code != '200'
      puts "Failed to download: #{response.code}"
      exit 1
    end
    
    gz = Zlib::GzipReader.new(StringIO.new(response.body))
    event_samples = {}
    
    gz.each_line.with_index do |line, index|
      begin
        event = JSON.parse(line)
        type = event['type']
        
        # Collect one sample of each relevant event type
        if %w[PushEvent ReleaseEvent ForkEvent CreateEvent WatchEvent].include?(type) && !event_samples[type]
          event_samples[type] = event
          
          puts "\n#{'='*60}"
          puts "#{type} (line #{index + 1})"
          puts "#{'='*60}"
          puts JSON.pretty_generate(event)
          
          # Stop after we have all event types
          if event_samples.size == 5
            puts "\n\nCollected all event types!"
            break
          end
        end
      rescue JSON::ParserError => e
        # Skip malformed lines
      end
    end
    
    puts "\n\nSummary of repository data available in each event type:"
    event_samples.each do |type, event|
      puts "\n#{type}:"
      puts "  repo: #{event['repo'].inspect}"
      puts "  org: #{event['org'].inspect}" if event['org']
      
      case type
      when 'ForkEvent'
        if event['payload']['forkee']
          puts "  forkee fields: #{event['payload']['forkee'].keys.sort.join(', ')}"
        end
      when 'CreateEvent'
        puts "  payload: #{event['payload'].inspect}"
      when 'PushEvent'
        puts "  payload keys: #{event['payload'].keys.join(', ')}"
      when 'ReleaseEvent'
        if event['payload']['release']
          puts "  release fields: #{event['payload']['release'].keys.sort.join(', ')}"
        end
      end
    end
  end
  
  desc "Show import status"
  task status: :environment do
    total = Import.count
    successful = Import.successful.count
    failed = Import.failed.count
    
    puts "Import Status:"
    puts "Total imports: #{total}"
    puts "Successful: #{successful}"
    puts "Failed: #{failed}"
    
    if total > 0
      puts "\nRecent imports:"
      Import.recent.limit(10).each do |import|
        status = import.success? ? "✓" : "✗"
        stats = []
        stats << "#{import.push_events_count} push events" if import.push_events_count && import.push_events_count > 0
        stats << "#{import.release_events_count} release events" if import.release_events_count && import.release_events_count > 0
        stats << "#{import.repositories_synced_count} repos synced" if import.repositories_synced_count && import.repositories_synced_count > 0
        stats << "#{import.releases_synced_count} releases synced" if import.releases_synced_count && import.releases_synced_count > 0
        
        puts "#{status} #{import.filename} - #{import.imported_at} #{stats.join(', ')}"
        puts "  Error: #{import.error_message}" if import.error_message.present?
      end
    end
    
    # Show coverage gaps
    now = Time.current.utc
    end_time = now - 2.hours
    start_time = end_time - 24.hours
    
    missing = []
    (start_time.to_date..end_time.to_date).each do |date|
      24.times do |hour|
        timestamp = date.to_time + hour.hours
        next if timestamp < start_time || timestamp > end_time
        
        unless Import.already_imported?(date, hour)
          missing << "#{date} hour #{hour}"
        end
      end
    end
    
    if missing.any?
      puts "\nMissing imports in last 24 hours:"
      missing.each { |m| puts "  - #{m}" }
    else
      puts "\nAll hours in the last 24 hours have been imported."
    end
  end
  
  desc "Retry failed imports"
  task retry_failed: :environment do
    Rails.logger = Logger.new(STDOUT)
    
    failed_imports = Import.failed.recent.limit(10)
    
    if failed_imports.empty?
      puts "No failed imports to retry."
    else
      puts "Retrying #{failed_imports.count} failed imports..."
      
      failed_imports.each do |import|
        puts "Retrying #{import.filename}..."
        success = import.retry!
        puts success ? "✓ Success" : "✗ Failed"
      end
    end
  end
end