# Rails console script to analyze Scorecard records
# Usage: Load this in Rails console with: load 'scorecard_analysis.rb'

puts "Starting Scorecard analysis..."

# Helper method to format large numbers
def format_number(num)
  case num
  when 0..999
    num.to_s
  when 1_000..999_999
    "#{(num / 1_000.0).round(1)}K"
  when 1_000_000..999_999_999
    "#{(num / 1_000_000.0).round(1)}M"
  else
    "#{(num / 1_000_000_000.0).round(1)}B"
  end
end

# Initialize aggregated stats
stats = {
  total_records: 0,
  with_data: 0,
  without_data: 0,
  errors: 0,
  scores: [],
  scored_repos: [],  # Store repo info with scores for top/bottom analysis
  versions: Hash.new(0),
  checks_summary: Hash.new { |h, k| h[k] = { count: 0, total_score: 0, scores: [] } },
  risk_levels: Hash.new { |h, k| h[k] = { count: 0, total_achieved: 0, total_possible: 0 } },
  dates: [],
  commits: []
}

puts "Processing Scorecard records..."

# Process each scorecard record
Scorecard.find_each(batch_size: 1000) do |scorecard|
  stats[:total_records] += 1
  
  begin
    if scorecard.data.present?
      stats[:with_data] += 1
      
      # Score analysis with validation
      if scorecard.score && scorecard.score.is_a?(Numeric) && scorecard.score >= 0 && scorecard.score <= 10
        stats[:scores] << scorecard.score
        
        # Store repo info for top/bottom analysis (avoid DB lookup)
        repo_name = scorecard.data.dig("repo", "name") || "Repo ID #{scorecard.repository_id}"
        stats[:scored_repos] << { name: repo_name, score: scorecard.score }
      end
      
      # Version analysis with validation
      if scorecard.scorecard_version && scorecard.scorecard_version.is_a?(String)
        stats[:versions][scorecard.scorecard_version] += 1
      end
      
      # Date analysis with validation
      if scorecard.generated_at && scorecard.generated_at.is_a?(String)
        begin
          parsed_date = Time.parse(scorecard.generated_at)
          # Only include dates from last 5 years to filter out obviously invalid dates
          if parsed_date > Time.now - 5.years && parsed_date <= Time.now
            stats[:dates] << scorecard.generated_at
          end
        rescue ArgumentError
          # Skip invalid date strings
        end
      end
      
      # Commit analysis with validation
      if scorecard.commit && scorecard.commit.is_a?(String) && scorecard.commit.length >= 7
        stats[:commits] << scorecard.commit
      end
      
      # Checks analysis with error handling
      if scorecard.checks && scorecard.checks.is_a?(Array)
        scorecard.checks.each do |check|
          next unless check.is_a?(Hash)
          
          check_name = check['name']
          check_score = check['score']
          
          next unless check_name.is_a?(String) && check_score.is_a?(Numeric)
          next unless check_score >= -1 && check_score <= 10  # -1 is valid (not applicable)
          
          stats[:checks_summary][check_name][:count] += 1
          if check_score != -1  # -1 means not applicable
            stats[:checks_summary][check_name][:total_score] += check_score
            stats[:checks_summary][check_name][:scores] << check_score
          end
        end
      end
      
      # Risk level analysis with error handling
      begin
        risk_summary = scorecard.risk_summary
        if risk_summary.is_a?(Hash)
          risk_summary.each do |level, data|
            next if level == :not_applicable
            next unless data.is_a?(Hash) && data.key?(:achieved) && data.key?(:total)
            
            stats[:risk_levels][level][:count] += 1
            stats[:risk_levels][level][:total_achieved] += data[:achieved].to_i
            stats[:risk_levels][level][:total_possible] += data[:total].to_i
          end
        end
      rescue => e
        # Skip records with invalid risk summary data
      end
    else
      stats[:without_data] += 1
    end
    
  rescue => e
    stats[:errors] += 1
    puts "Error processing scorecard ID #{scorecard.id}: #{e.message}" if stats[:errors] <= 10
  end
  
  # Progress indicator
  if stats[:total_records] % 10000 == 0
    puts "Processed #{format_number(stats[:total_records])} records..."
  end
end

puts "\n" + "="*80
puts "SCORECARD ANALYSIS SUMMARY"
puts "="*80

# Overall stats and error reporting
puts "#{format_number(stats[:total_records])} repositories analyzed (#{(stats[:with_data].to_f / stats[:total_records] * 100).round(1)}% with data)"
if stats[:errors] > 0
  puts "#{format_number(stats[:errors])} records had processing errors and were skipped"
end

# Overall stats and scores
if stats[:scores].any?
  score_ranges = {
    "0-2" => stats[:scores].count { |s| s >= 0 && s < 2 },
    "2-4" => stats[:scores].count { |s| s >= 2 && s < 4 },
    "4-6" => stats[:scores].count { |s| s >= 4 && s < 6 },
    "6-8" => stats[:scores].count { |s| s >= 6 && s < 8 },
    "8-10" => stats[:scores].count { |s| s >= 8 && s <= 10 }
  }
  
  puts "Average score: #{(stats[:scores].sum.to_f / stats[:scores].length).round(2)} (range: #{stats[:scores].min}-#{stats[:scores].max})"
  puts "Distribution: #{score_ranges.map { |k,v| "#{k}: #{(v.to_f/stats[:scores].length*100).round(1)}%" }.join(', ')}"
else
  puts "No valid score data found"
end

# Top issues (worst performing checks)
if stats[:checks_summary].any?
  puts "\nTOP SECURITY CONCERNS:"
  worst_checks = stats[:checks_summary]
    .select { |k, v| v[:scores].length > stats[:total_records] * 0.5 }
    .sort_by { |k, v| v[:total_score].to_f / v[:scores].length }
    .first(5)
  
  worst_checks.each do |check_name, data|
    avg_score = (data[:total_score].to_f / data[:scores].length).round(1)
    puts "  #{check_name}: #{avg_score}/10 average (#{format_number(data[:count])} repos)"
  end
end

# Strong areas
if stats[:checks_summary].any?
  puts "\nSTRONG AREAS:"
  best_checks = stats[:checks_summary]
    .select { |k, v| v[:scores].length > stats[:total_records] * 0.5 }
    .sort_by { |k, v| v[:total_score].to_f / v[:scores].length }
    .last(3)
  
  best_checks.each do |check_name, data|
    avg_score = (data[:total_score].to_f / data[:scores].length).round(1)
    puts "  #{check_name}: #{avg_score}/10 average (#{format_number(data[:count])} repos)"
  end
end

# Risk level summary
if stats[:risk_levels].any?
  puts "\nRISK LEVEL ACHIEVEMENT:"
  ['critical', 'high', 'medium', 'low'].each do |level|
    data = stats[:risk_levels][level.to_sym]
    next if data[:count] == 0
    
    avg_percentage = data[:total_possible] > 0 ? 
      (data[:total_achieved].to_f / data[:total_possible] * 100).round(1) : 0
    
    puts "  #{level.capitalize}: #{avg_percentage}% achievement rate"
  end
end

# Version and date summary
if stats[:versions].any?
  top_version = stats[:versions].sort_by { |k, v| -v }.first
  puts "\nMost common scorecard version: #{top_version[0]} (#{(top_version[1].to_f / stats[:with_data] * 100).round(1)}%)"
end

# Top and bottom repositories
if stats[:scored_repos].any?
  puts "\nTOP 3 REPOSITORIES:"
  top_repos = stats[:scored_repos].sort_by { |r| -r[:score] }.first(3)
  top_repos.each_with_index do |repo, index|
    puts "  #{index + 1}. #{repo[:name]}: #{repo[:score]}"
  end
  
  puts "\nBOTTOM 3 REPOSITORIES:"
  bottom_repos = stats[:scored_repos].sort_by { |r| r[:score] }.first(3)
  bottom_repos.each_with_index do |repo, index|
    puts "  #{index + 1}. #{repo[:name]}: #{repo[:score]}"
  end
end

if stats[:dates].any?
  parsed_dates = stats[:dates].map { |d| Time.parse(d) rescue nil }.compact
  if parsed_dates.any?
    recent_count = parsed_dates.count { |d| d > Time.now - 30.days }
    puts "\nRecent analysis: #{format_number(recent_count)} repositories scanned in last 30 days"
  end
end

puts "\n" + "="*80
puts "Analysis complete!"
puts "="*80